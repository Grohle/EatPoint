import 'dart:convert';

import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';

/// EatPoint: the foods the user always has in a meal (milk at breakfast,
/// bread every morning), by meal id, kept for the next menu generated.
class FixedFoodsStore {
  static const _key = 'generator.fixed';

  final HiveDBProvider _db;

  FixedFoodsStore(this._db);

  Map<String, List<PlannedItem>> get() {
    final raw = _db.pointsSettingsBox.get(_key);
    if (raw == null) return const {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const {};
      return {
        for (final e in json.entries)
          if (e.key is String && e.value is List)
            e.key as String: [
              for (final i in e.value as List) ?PlannedItem.fromJson(i),
            ],
      };
    } on FormatException {
      return const {};
    }
  }

  Future<void> save(Map<String, List<PlannedItem>> fixed) =>
      _db.pointsSettingsBox.put(
        _key,
        jsonEncode({
          for (final e in fixed.entries)
            if (e.value.isNotEmpty)
              e.key: [for (final i in e.value) i.toJson()],
        }),
      );
}
