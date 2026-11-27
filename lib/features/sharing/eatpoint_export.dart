import 'dart:convert';

import 'package:opennutritracker/core/utils/hive_db_provider.dart';

/// Exports and imports EatPoint's own data for the active profile — points
/// settings, weekly menus, shopping lists, reminder times — as one JSON
/// document. The app's diary has its own export in Settings.
///
/// Never exported: the household membership and the other members'
/// snapshots (they belong to the household, not to this file) and the
/// agent connector's token.
class EatPointExport {
  static const format = 'eatpoint-export';
  static const version = 1;

  static bool _private(String key) =>
      key == 'household' ||
      key.startsWith('household:') ||
      key == 'mcp:config' ||
      key == 'mcp:proposals';

  final HiveDBProvider _db;

  EatPointExport(this._db);

  String exportJson({DateTime? now}) {
    final entries = <String, Object?>{};
    for (final key in _db.pointsSettingsBox.keys) {
      if (key is! String || _private(key)) continue;
      final raw = _db.pointsSettingsBox.get(key);
      if (raw == null) continue;
      try {
        entries[key] = jsonDecode(raw);
      } on FormatException {
        continue;
      }
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'entries': entries,
    });
  }

  /// Writes the entries of an export into the active profile, replacing
  /// entries with the same key. Returns how many entries were imported.
  /// Throws [FormatException] when [text] is not an EatPoint export.
  Future<int> importJson(String text) async {
    final decoded = jsonDecode(text);
    if (decoded is! Map ||
        decoded['format'] != format ||
        decoded['entries'] is! Map) {
      throw const FormatException('Not an EatPoint export');
    }
    final entries = decoded['entries'] as Map;
    final toWrite = <String, String>{
      for (final e in entries.entries)
        if (e.key is String && !_private(e.key as String))
          e.key as String: jsonEncode(e.value),
    };
    await _db.pointsSettingsBox.putAll(toWrite);
    return toWrite.length;
  }
}
