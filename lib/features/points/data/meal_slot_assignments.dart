import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

/// Remembers which of the user's meals each logged food belongs to.
///
/// The diary stores a food under one of four meal types. When the user has
/// more than one meal of a type (say "Mid-morning" and "Afternoon snack",
/// both snacks), this tells them apart. Stored per day under
/// `slots:YYYY-MM-DD` as `{intakeId: mealId}`.
class MealSlotAssignments {
  static const _prefix = 'slots:';

  final _log = Logger('MealSlotAssignments');
  final HiveDBProvider _db;
  // Parsed days, keyed by the stored JSON so a write from elsewhere (an
  // import, a profile switch) is never served stale.
  final Map<String, ({String raw, Map<String, String> map})> _cache = {};

  /// Bumped on every change so open screens can regroup.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  MealSlotAssignments(this._db);

  static String _key(DateTime d) =>
      '$_prefix${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, String> _day(DateTime d) {
    final key = _key(d);
    final raw = _db.pointsSettingsBox.get(key);
    if (raw == null) return const {};
    final cached = _cache[key];
    if (cached != null && cached.raw == raw) return cached.map;
    final map = <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final e in decoded.entries) {
          if (e.key is String && e.value is String) {
            map[e.key as String] = e.value as String;
          }
        }
      }
    } on FormatException catch (e) {
      _log.warning('Unreadable meal assignments $key: $e');
    }
    _cache[key] = (raw: raw, map: map);
    return map;
  }

  String? slotIdOf(IntakeEntity intake) => _day(intake.dateTime)[intake.id];

  Future<void> assign(IntakeEntity intake, String slotId) async {
    final key = _key(intake.dateTime);
    final day = Map<String, String>.from(_day(intake.dateTime));
    if (day[intake.id] == slotId) return;
    day[intake.id] = slotId;
    await _db.pointsSettingsBox.put(key, jsonEncode(day));
    revision.value++;
  }

  /// The meal [intake] belongs to: the one it was logged in when that meal
  /// still exists and still stores foods as the intake's type, otherwise the
  /// first meal of that type. Null when the user has no meal of that type.
  MealSlot? resolve(IntakeEntity intake, List<MealSlot> slots) {
    final id = slotIdOf(intake);
    if (id != null) {
      final slot = slots.byId(id);
      if (slot != null && slot.baseType == intake.type) return slot;
    }
    return slots.defaultFor(intake.type);
  }

  /// [intakes] grouped by meal, in the order of [slots]. Foods whose type
  /// has no meal any more come back in [MealSlotGrouping.orphans].
  MealSlotGrouping group(Iterable<IntakeEntity> intakes, List<MealSlot> slots) {
    final bySlot = {for (final s in slots) s.id: <IntakeEntity>[]};
    final orphans = <IntakeTypeEntity, List<IntakeEntity>>{};
    for (final intake in intakes) {
      final slot = resolve(intake, slots);
      if (slot == null) {
        (orphans[intake.type] ??= []).add(intake);
      } else {
        bySlot[slot.id]!.add(intake);
      }
    }
    return MealSlotGrouping(bySlot: bySlot, orphans: orphans);
  }
}

class MealSlotGrouping {
  final Map<String, List<IntakeEntity>> bySlot;
  final Map<IntakeTypeEntity, List<IntakeEntity>> orphans;

  const MealSlotGrouping({required this.bySlot, required this.orphans});
}

/// The meal the user is adding food to right now.
///
/// Screens that add food to a meal set it before opening the add flow; any
/// food logged under the same type while it is set goes to that meal. It is
/// cleared when the user is back on the screen they started from (see
/// [MealSlotRouteObserver]) so a later, unrelated add is not affected.
class MealSlotContext {
  MealSlotContext._();

  static ({String slotId, IntakeTypeEntity type})? _pending;

  static ({String slotId, IntakeTypeEntity type})? get pending => _pending;

  static void select(MealSlot slot) =>
      _pending = (slotId: slot.id, type: slot.baseType);

  static void clear() => _pending = null;

  /// Runs [body] with [slot] selected, then clears it.
  static Future<T> run<T>(MealSlot slot, Future<T> Function() body) async {
    select(slot);
    try {
      return await body();
    } finally {
      clear();
    }
  }

  /// Called by the diary's repository after a food was logged.
  static void onIntakeAdded(IntakeEntity intake, MealSlotAssignments store) {
    final pending = _pending;
    if (pending == null || pending.type != intake.type) return;
    store.assign(intake, pending.slotId);
  }
}

/// Clears [MealSlotContext] whenever the navigator is back at its first
/// route, i.e. the user has left the add-food flow.
class MealSlotRouteObserver extends NavigatorObserver {
  int _depth = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _depth++;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _back(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _back(previousRoute);

  void _back(Route<dynamic>? previousRoute) {
    if (_depth > 0) _depth--;
    if (previousRoute == null || previousRoute.isFirst || _depth <= 1) {
      MealSlotContext.clear();
    }
  }
}
