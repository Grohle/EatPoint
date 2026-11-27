import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';

/// Stores the weekly planner, shopping-list ticks and reminder times for the
/// active profile in EatPoint's per-profile box.
class PlannerDataSource {
  static const _planPrefix = 'plan:';
  static const _shoppingPrefix = 'shop:';
  static const _remindersKey = 'reminders';

  final _log = Logger('PlannerDataSource');
  final HiveDBProvider _db;

  /// Bumped on every write so open screens can reload.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  PlannerDataSource(this._db);

  Map<String, dynamic>? _readJson(String key) {
    final raw = _db.pointsSettingsBox.get(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException catch (e) {
      _log.warning('Unreadable planner entry $key: $e');
      return null;
    }
  }

  Future<void> _writeJson(String key, Map<String, dynamic> json) async {
    await _db.pointsSettingsBox.put(key, jsonEncode(json));
    revision.value++;
  }

  DayPlan getDay(DateTime date) {
    final json = _readJson('$_planPrefix${DayPlan.dateKey(date)}');
    return json == null ? DayPlan.empty(date) : DayPlan.fromJson(json, date);
  }

  /// Monday to Sunday of the week [anyDay] falls in.
  List<DayPlan> getWeek(DateTime anyDay) {
    final start = DayPlan.weekStart(anyDay);
    return [for (var i = 0; i < 7; i++) getDay(start.add(Duration(days: i)))];
  }

  Future<void> saveDay(DayPlan plan) async {
    final key = '$_planPrefix${DayPlan.dateKey(plan.date)}';
    if (plan.isEmpty && plan.logged.isEmpty) {
      await _db.pointsSettingsBox.delete(key);
      revision.value++;
      return;
    }
    await _writeJson(key, plan.toJson());
  }

  /// Copies every day of the week before [weekStart] into that week,
  /// replacing what it held. Returns how many days had something to copy.
  Future<int> copyPreviousWeek(DateTime weekStart) async {
    final start = DayPlan.weekStart(weekStart);
    var copied = 0;
    for (var i = 0; i < 7; i++) {
      final from = getDay(start.subtract(Duration(days: 7 - i)));
      if (from.isEmpty) continue;
      await saveDay(from.copyTo(start.add(Duration(days: i))));
      copied++;
    }
    return copied;
  }

  ShoppingListState getShopping(DateTime anyDay) {
    final key = '$_shoppingPrefix${DayPlan.dateKey(DayPlan.weekStart(anyDay))}';
    final json = _readJson(key);
    return json == null
        ? const ShoppingListState()
        : ShoppingListState.fromJson(json);
  }

  Future<void> saveShopping(DateTime anyDay, ShoppingListState state) =>
      _writeJson(
        '$_shoppingPrefix${DayPlan.dateKey(DayPlan.weekStart(anyDay))}',
        state.toJson(),
      );

  PlannerReminderSettings getReminders() {
    final json = _readJson(_remindersKey);
    return json == null
        ? PlannerReminderSettings.off
        : PlannerReminderSettings.fromJson(json);
  }

  Future<void> saveReminders(PlannerReminderSettings settings) =>
      _writeJson(_remindersKey, settings.toJson());

  /// Every stored day plan, oldest first. Used by export and sync.
  List<DayPlan> allDays() {
    final plans = <DayPlan>[];
    for (final key in _db.pointsSettingsBox.keys) {
      if (key is String && key.startsWith(_planPrefix)) {
        final json = _readJson(key);
        final date = DateTime.tryParse(key.substring(_planPrefix.length));
        if (json != null && date != null) {
          plans.add(DayPlan.fromJson(json, date));
        }
      }
    }
    plans.sort((a, b) => a.date.compareTo(b.date));
    return plans;
  }
}
