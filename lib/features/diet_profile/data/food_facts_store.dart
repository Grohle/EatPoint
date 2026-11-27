import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diet_profile/domain/food_facts.dart';
import 'package:opennutritracker/features/food_db/domain/food_database.dart';

/// Keeps what labels and Open Food Facts said about foods, by the food's
/// code (barcode or custom food id), so the diet check can use it every
/// time the food comes up again.
class FoodFactsStore {
  static const _prefix = 'facts:';

  final _log = Logger('FoodFactsStore');
  final HiveDBProvider _db;

  /// Recent lookups, so lists don't decode JSON for every row.
  final Map<String, FoodFacts?> _cache = {};

  FoodFactsStore(this._db);

  FoodFacts? get(String? code) {
    if (code == null || code.isEmpty) return null;
    if (_cache.containsKey(code)) return _cache[code];
    FoodFacts? facts;
    final raw = _db.pointsSettingsBox.get('$_prefix$code');
    if (raw != null) {
      try {
        facts = FoodFacts.fromJson(jsonDecode(raw));
      } on FormatException catch (e) {
        _log.warning('Unreadable food facts for $code: $e');
      }
    }
    return _cache[code] = facts;
  }

  Future<void> save(String? code, FoodFacts facts) async {
    if (code == null || code.isEmpty) return;
    if (facts.isEmpty) {
      _cache[code] = null;
      await _db.pointsSettingsBox.delete('$_prefix$code');
      return;
    }
    _cache[code] = facts;
    await _db.pointsSettingsBox.put(
      '$_prefix$code',
      jsonEncode(facts.toJson()),
    );
  }

  /// The facts stored for [code], when the store is set up, else what the
  /// downloaded food database says about it.
  static FoodFacts? lookup(String? code) {
    final stored = locator.isRegistered<FoodFactsStore>()
        ? locator<FoodFactsStore>().get(code)
        : null;
    return stored ?? FoodDatabase.instance?.byCode(code)?.facts;
  }

  /// Stores [facts] for [code] when the store is set up; never throws.
  static Future<void> record(String? code, FoodFacts facts) async {
    if (!locator.isRegistered<FoodFactsStore>()) return;
    try {
      await locator<FoodFactsStore>().save(code, facts);
    } catch (e) {
      Logger('FoodFactsStore').warning('Could not store food facts: $e');
    }
  }

  /// Forgets cached lookups (after a profile switch).
  void clearCache() => _cache.clear();
}
