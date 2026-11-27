import 'package:logging/logging.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/sync/domain/household_menu.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_crypto.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';

/// Result of one sync round.
class HouseholdSyncResult {
  final int membersSeen;
  final bool listChanged;
  final List<String> unreadable;

  const HouseholdSyncResult({
    required this.membersSeen,
    required this.listChanged,
    this.unreadable = const [],
  });
}

typedef SyncBackendBuilder =
    SyncBackend Function(
      SyncBackendConfig config, {
      required String householdId,
      required String? secret,
    });

/// Exchanges menus and shopping-list ticks with the other members of the
/// household through the configured backend. Everything that leaves the
/// phone is encrypted with the household key first.
class HouseholdSyncService {
  /// Days published around today: last week to three weeks ahead.
  static const daysBack = 7;
  static const daysAhead = 21;

  final _log = Logger('HouseholdSyncService');
  final PlannerDataSource _planner;
  final HouseholdStore _store;
  final SyncBackendBuilder _backendBuilder;

  /// EatPoint: this member's meals, points and diet, shared when they allow
  /// changes to their menu. Null in builds and tests without it.
  final Future<MemberProfile?> Function()? _profile;

  bool _running = false;

  HouseholdSyncService(
    this._planner,
    this._store,
    this._backendBuilder, {
    Future<MemberProfile?> Function()? profile,
  }) : _profile = profile;

  /// Builds this member's snapshot from the local planner.
  MemberSnapshot buildMySnapshot(
    Household household, {
    DateTime? now,
    MemberProfile? profile,
  }) {
    final today = DayPlan.dateOnly(now ?? DateTime.now());
    final days = <DayPlan>[];
    for (var i = -daysBack; i <= daysAhead; i++) {
      final day = _planner.getDay(today.add(Duration(days: i)));
      if (!day.isEmpty || day.logged.isNotEmpty) days.add(day);
    }
    final shopping = <String, ShoppingListState>{};
    for (var w = -1; w <= 3; w++) {
      final weekDay = today.add(Duration(days: 7 * w));
      final state = _planner.getShopping(weekDay);
      if (state.checked.isNotEmpty ||
          state.manualItems.isNotEmpty ||
          state.tickTimes.isNotEmpty ||
          state.removedManual.isNotEmpty) {
        shopping[DayPlan.dateKey(DayPlan.weekStart(weekDay))] = state;
      }
    }
    return MemberSnapshot(
      memberId: household.memberId,
      name: household.memberName,
      updatedAt: now ?? DateTime.now(),
      days: days,
      shopping: shopping,
      profile: profile,
      edits: _store.pendingEdits(),
      applied: _store.appliedEdits(),
    );
  }

  Future<MemberProfile?> _myProfile() async {
    final allow = _store.allowEdits;
    if (!allow) return const MemberProfile(allowEdits: false);
    try {
      final profile = await _profile?.call();
      return profile == null
          ? const MemberProfile()
          : MemberProfile(
              slots: profile.slots,
              budgets: profile.budgets,
              fibre: profile.fibre,
              diet: profile.diet,
            );
    } catch (e) {
      _log.warning('Profile not shared this round: $e');
      return const MemberProfile();
    }
  }

  /// Applies the changes [other] made to this member's menu, when this
  /// member allows it, and remembers each as handled either way. A meal
  /// already logged is left as it is. Returns whether the menu changed.
  Future<bool> _applyEdits(Household household, MemberSnapshot other) async {
    final handled = _store.appliedEdits();
    final incoming = [
      for (final e in other.edits)
        if (e.memberId == household.memberId && !handled.contains(e.id)) e,
    ]..sort((a, b) => a.at.compareTo(b.at));
    if (incoming.isEmpty) return false;
    var changed = false;
    if (_store.allowEdits) {
      for (final edit in incoming) {
        final day = _planner.getDay(edit.date);
        if (day.logged.contains(edit.slotId)) continue;
        await _planner.saveDay(edit.applyTo(day));
        changed = true;
      }
    }
    await _store.markApplied(incoming.map((e) => e.id));
    if (changed) _log.fine('Menu changed by ${other.memberId}');
    return true;
  }

  /// One sync round. Returns null when no household is set up or another
  /// round is already running.
  Future<HouseholdSyncResult?> syncNow({DateTime? now}) async {
    if (_running) return null;
    final household = _store.getHousehold();
    if (household == null) return null;
    final key = await _store.readKey();
    if (key == null) {
      throw SyncBackendException('The household key is missing');
    }
    _running = true;
    try {
      final backend = _backendBuilder(
        household.backend,
        householdId: household.householdId,
        secret: await _store.readBackendSecret(),
      );

      final profile = await _myProfile();
      Future<void> publish() async => backend.put(
        household.blobName,
        await HouseholdCrypto.encryptJson(
          buildMySnapshot(household, now: now, profile: profile).toJson(),
          key,
          household.householdId,
        ),
      );
      await publish();
      var republish = false;

      final names = await backend.list();
      final members = <String, String>{...household.members};
      final unreadable = <String>[];
      var listChanged = false;
      var seen = 0;
      for (final name in names) {
        final memberId = Household.memberIdFromBlob(name);
        if (memberId == null || memberId == household.memberId) continue;
        final blob = await backend.get(name);
        if (blob == null) continue;
        final MemberSnapshot? snapshot;
        try {
          snapshot = MemberSnapshot.fromJson(
            await HouseholdCrypto.decryptJson(blob, key, household.householdId),
          );
        } on HouseholdDecryptionException {
          unreadable.add(name);
          continue;
        }
        if (snapshot == null) continue;
        seen++;
        members[snapshot.memberId] = snapshot.name;
        await _store.confirmEdits(snapshot.memberId, snapshot.applied);
        await _store.saveMember(_withPending(snapshot));
        listChanged |= await _mergeShopping(snapshot);
        republish |= await _applyEdits(household, snapshot);
      }
      // What was applied (and the confirmations) reach the others now
      // rather than on the next round.
      if (republish) await publish();
      await _store.saveHousehold(
        household.copyWith(members: members, lastSyncAt: now ?? DateTime.now()),
      );
      return HouseholdSyncResult(
        membersSeen: seen,
        listChanged: listChanged,
        unreadable: unreadable,
      );
    } finally {
      _running = false;
    }
  }

  /// [snapshot] with this phone's unconfirmed changes to it still shown.
  MemberSnapshot _withPending(MemberSnapshot snapshot) {
    var result = snapshot;
    for (final edit in _store.pendingEdits()) {
      if (edit.memberId != snapshot.memberId) continue;
      final day = result.dayFor(edit.date) ?? DayPlan.empty(edit.date);
      result = result.withDay(edit.applyTo(day));
    }
    return result;
  }

  Future<bool> _mergeShopping(MemberSnapshot other) async {
    var changed = false;
    for (final entry in other.shopping.entries) {
      final week = DateTime.tryParse(entry.key);
      if (week == null) continue;
      final local = _planner.getShopping(week);
      final merged = local.mergeWith(entry.value);
      if (!merged.sameAs(local)) {
        await _planner.saveShopping(week, merged);
        changed = true;
      }
    }
    if (changed) _log.fine('Shopping list merged from ${other.memberId}');
    return changed;
  }
}
