import 'package:flutter/foundation.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';

/// How often a copy goes to Google Drive by itself.
enum AutoBackup { off, daily, weekly }

/// Backup preferences: the automatic copy, when the last one was made and
/// where it goes in Google Drive.
class BackupSettings {
  static const _autoKey = 'backup.auto';
  static const _lastKey = 'backup.lastAt';
  static const _folderKey = 'backup.driveFolder';
  static const _clientKey = 'backup.driveClientId';

  /// Copies kept in Drive; older ones go to the bin.
  static const keep = 10;

  final HiveDBProvider _db;
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  BackupSettings(this._db);

  String? _get(String key) {
    final raw = _db.pointsSettingsBox.get(key);
    if (raw == null) return null;
    // Stored as JSON strings, like every EatPoint setting.
    return raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')
        ? raw.substring(1, raw.length - 1)
        : raw;
  }

  Future<void> _put(String key, String? value) async {
    if (value == null) {
      await _db.pointsSettingsBox.delete(key);
    } else {
      await _db.pointsSettingsBox.put(key, '"$value"');
    }
    revision.value++;
  }

  AutoBackup get auto =>
      AutoBackup.values.where((a) => a.name == _get(_autoKey)).firstOrNull ??
      AutoBackup.off;
  Future<void> setAuto(AutoBackup value) => _put(_autoKey, value.name);

  DateTime? get lastAt => DateTime.tryParse(_get(_lastKey) ?? '');
  Future<void> setLastAt(DateTime at) => _put(_lastKey, at.toIso8601String());

  String? get driveFolder => _get(_folderKey);
  Future<void> setDriveFolder(String? id) => _put(_folderKey, id);

  String? get driveClientId => _get(_clientKey);
  Future<void> setDriveClientId(String? id) =>
      _put(_clientKey, id == null || id.trim().isEmpty ? null : id.trim());

  /// Whether an automatic copy is due at [now].
  bool due(DateTime now) {
    final last = lastAt;
    return switch (auto) {
      AutoBackup.off => false,
      AutoBackup.daily =>
        last == null || now.difference(last) >= const Duration(hours: 20),
      AutoBackup.weekly =>
        last == null || now.difference(last) >= const Duration(days: 7),
    };
  }
}
