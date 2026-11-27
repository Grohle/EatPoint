import 'package:logging/logging.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
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

  bool _running = false;

  HouseholdSyncService(this._planner, this._store, this._backendBuilder);

  /// Builds this member's snapshot from the local planner.
  MemberSnapshot buildMySnapshot(Household household, {DateTime? now}) {
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
    );
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

      final mine = buildMySnapshot(household, now: now);
      await backend.put(
        household.blobName,
        await HouseholdCrypto.encryptJson(
          mine.toJson(),
          key,
          household.householdId,
        ),
      );

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
        await _store.saveMember(snapshot);
        listChanged |= await _mergeShopping(snapshot);
      }
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
