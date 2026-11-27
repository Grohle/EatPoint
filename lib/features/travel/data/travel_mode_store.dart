import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/travel/domain/travel_mode.dart';

/// Stores [TravelMode] for the active profile in EatPoint's box.
class TravelModeStore {
  static const _key = 'travel';

  final _log = Logger('TravelModeStore');
  final HiveDBProvider _db;

  /// Bumped on every change so open screens can update.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  TravelModeStore(this._db);

  TravelMode get() {
    final raw = _db.pointsSettingsBox.get(_key);
    if (raw == null) return TravelMode.off;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return TravelMode.fromJson(decoded);
    } on FormatException catch (e) {
      _log.warning('Unreadable travel mode, treating it as off: $e');
    }
    return TravelMode.off;
  }

  /// Travel mode as it applies right now. A trip whose last day has passed
  /// counts as over.
  TravelMode current({DateTime? now}) {
    final mode = get();
    return mode.isActiveAt(now ?? DateTime.now())
        ? mode
        : mode.copyWith(enabled: false);
  }

  bool isActive({DateTime? now}) => current(now: now).enabled;

  Future<void> save(TravelMode mode) async {
    await _db.pointsSettingsBox.put(_key, jsonEncode(mode.toJson()));
    revision.value++;
  }

  Future<void> setEnabled(bool enabled, {DateTime? now}) async {
    final mode = get();
    await save(
      mode.copyWith(
        enabled: enabled,
        since: enabled ? () => now ?? DateTime.now() : null,
        // A new trip starts without the last one's end date.
        until: enabled && mode.hasExpiredAt(now ?? DateTime.now())
            ? () => null
            : null,
      ),
    );
  }

  /// Turns travel mode off for good once its last day has passed, so the
  /// paused features come back. Returns true when it did.
  Future<bool> endIfExpired({DateTime? now}) async {
    final mode = get();
    if (!mode.hasExpiredAt(now ?? DateTime.now())) return false;
    await save(mode.copyWith(enabled: false, until: () => null));
    return true;
  }
}

/// Quick checks for screens that only need to know what is paused.
class TravelModeGate {
  TravelModeGate._();

  static TravelMode get _mode => locator.isRegistered<TravelModeStore>()
      ? locator<TravelModeStore>().current()
      : TravelMode.off;

  static bool get active => _mode.enabled;
  static bool get plannerPaused => _mode.enabled && _mode.pausePlanner;
  static bool get remindersPaused => _mode.enabled && _mode.pauseReminders;
  static bool get householdSyncPaused =>
      _mode.enabled && _mode.pauseHouseholdSync;
  static bool get dailyBudgetOnly => _mode.enabled && _mode.dailyBudgetOnly;
}
