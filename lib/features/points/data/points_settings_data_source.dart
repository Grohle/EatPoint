import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';

/// Reads and writes [PointsSettings] for the active profile.
class PointsSettingsDataSource {
  static const _settingsKey = 'PointsSettings';

  final _log = Logger('PointsSettingsDataSource');
  final HiveDBProvider _db;

  PointsSettingsDataSource(this._db);

  /// Bumped on every save so open screens can reload.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// The stored settings, or the defaults when nothing is stored or the
  /// stored value cannot be read.
  Future<PointsSettings> getSettings() async {
    final raw = _db.pointsSettingsBox.get(_settingsKey);
    if (raw == null) return PointsSettings.defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PointsSettings.fromJson(decoded);
      }
    } on FormatException catch (e) {
      _log.warning('Unreadable points settings, using defaults: $e');
    }
    return PointsSettings.defaults;
  }

  Future<void> saveSettings(PointsSettings settings) async {
    await _db.pointsSettingsBox.put(
      _settingsKey,
      jsonEncode(settings.toJson()),
    );
    revision.value++;
  }

  Future<void> clear() async {
    await _db.pointsSettingsBox.delete(_settingsKey);
    revision.value++;
  }
}
