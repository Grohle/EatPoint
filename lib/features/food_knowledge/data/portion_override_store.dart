import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';

/// The user's own unit weights ("my tortillas weigh 40 g"), by food, kept
/// in the active profile and included in backups.
class PortionOverrideStore {
  static const _key = 'portionOverrides';

  final HiveDBProvider _db;

  /// Bumped on every change so open screens can update.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  PortionOverrideStore(this._db);

  /// A food is known by its code when it has one, else by its name.
  static String keyFor(String name, String? code) =>
      code != null && code.isNotEmpty
      ? 'code:$code'
      : 'name:${FoodKnowledge.fold(name).trim()}';

  Map<String, dynamic> _all() {
    final raw = _db.pointsSettingsBox.get(_key);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? json : {};
    } on FormatException {
      return {};
    }
  }

  /// The user's portion for this food: by code first, then by name.
  FoodPortion? portionFor(String name, String? code) {
    final all = _all();
    final raw = all[keyFor(name, code)] ?? all[keyFor(name, null)];
    if (raw is! Map) return null;
    final grams = (raw['g'] as num?)?.toDouble() ?? 0;
    if (grams <= 0) return null;
    String text(String k, String fallback) =>
        (raw[k] as String?)?.trim().isNotEmpty == true ? raw[k] : fallback;
    return FoodPortion(
      unit: 'piece',
      es: (one: text('es1', 'unidad'), other: text('es2', 'unidades')),
      en: (one: text('en1', 'unit'), other: text('en2', 'units')),
      grams: grams,
      isDefault: true,
    );
  }

  /// Saves [grams] per unit for the food, named [one]/[other] in the
  /// user's language ([languageCode]), under its code and its name.
  Future<void> save({
    required String name,
    String? code,
    required double grams,
    required String one,
    required String other,
    required String languageCode,
  }) async {
    final entry = <String, dynamic>{
      'g': grams,
      if (languageCode == 'es') ...{'es1': one, 'es2': other},
      if (languageCode != 'es') ...{'en1': one, 'en2': other},
    };
    final all = _all();
    all[keyFor(name, code)] = entry;
    if (code != null && code.isNotEmpty) all[keyFor(name, null)] = entry;
    await _db.pointsSettingsBox.put(_key, jsonEncode(all));
    revision.value++;
  }

  /// Goes back to the app's own weight for the food.
  Future<void> reset(String name, String? code) async {
    final all = _all()
      ..remove(keyFor(name, code))
      ..remove(keyFor(name, null));
    await _db.pointsSettingsBox.put(_key, jsonEncode(all));
    revision.value++;
  }

  bool hasOverride(String name, String? code) {
    final all = _all();
    return all.containsKey(keyFor(name, code)) ||
        all.containsKey(keyFor(name, null));
  }
}
