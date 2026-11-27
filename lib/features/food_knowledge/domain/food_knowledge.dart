import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

/// One household unit of a food, e.g. "1 filete" = 136 g.
class FoodPortion {
  final String unit;
  final ({String one, String other}) es;
  final ({String one, String other}) en;
  final double grams;
  final bool isDefault;

  const FoodPortion({
    required this.unit,
    required this.es,
    required this.en,
    required this.grams,
    this.isDefault = false,
  });

  /// The unit's name in [languageCode] for [count] of it.
  String name(String languageCode, double count) {
    final names = languageCode == 'es' ? es : en;
    // "½ aguacate" and "1 aguacate" are singular; "1½ filetes" is plural.
    return count > 1 ? names.other : names.one;
  }

  static FoodPortion? fromJson(Object? json) {
    if (json is! Map) return null;
    final es = json['es'], en = json['en'], grams = json['grams'];
    if (es is! List || es.length != 2 || en is! List || en.length != 2) {
      return null;
    }
    if (grams is! num || grams <= 0) return null;
    return FoodPortion(
      unit: json['unit'] as String? ?? '',
      es: (one: '${es[0]}', other: '${es[1]}'),
      en: (one: '${en[0]}', other: '${en[1]}'),
      grams: grams.toDouble(),
      isDefault: json['default'] == true,
    );
  }
}

/// An everyday food EatPoint knows by name: how it is portioned at home and
/// what kind of food it is (see `tool/food_knowledge/concepts.py`).
class FoodConcept {
  final String id;
  final List<String> namesEs;
  final List<String> namesEn;
  final Set<String> tags;
  final List<FoodPortion> portions;

  const FoodConcept({
    required this.id,
    required this.namesEs,
    required this.namesEn,
    required this.tags,
    required this.portions,
  });

  /// The portion to describe amounts with: the default one, else the first.
  FoodPortion? get mainPortion =>
      portions.where((p) => p.isDefault).firstOrNull ?? portions.firstOrNull;

  bool hasTag(String tag) => tags.contains(tag);

  static FoodConcept? fromJson(Object? json) {
    if (json is! Map) return null;
    final names = json['names'];
    if (json['id'] is! String || names is! Map) return null;
    List<String> list(Object? v) => [
      if (v is List)
        for (final n in v)
          if (n is String && n.isNotEmpty) n,
    ];
    return FoodConcept(
      id: json['id'] as String,
      namesEs: list(names['es']),
      namesEn: list(names['en']),
      tags: {...list(json['tags'])},
      portions: [
        if (json['portions'] is List)
          for (final p in json['portions'] as List) ?FoodPortion.fromJson(p),
      ],
    );
  }
}

/// A food EatPoint ships with full nutrition (USDA FoodData Central, public
/// domain), for planning and generating menus without a network.
class CoreFood {
  final String id;
  final String conceptId;
  final String nameEs;
  final String nameEn;
  final Set<String> tags;

  /// Nutrients per 100 g: kcal, carbs (available, without fibre), protein,
  /// fat, fibre, saturatedFat, sugars, sodiumMg, calciumMg, ironMg,
  /// vitaminCMg, vitaminDUg, vitaminB12Ug, folateUg, epaG, dhaG, alaG, …
  final Map<String, double> per100;
  final int? fdcId;

  const CoreFood({
    required this.id,
    required this.conceptId,
    required this.nameEs,
    required this.nameEn,
    required this.tags,
    required this.per100,
    this.fdcId,
  });

  String name(String languageCode) => languageCode == 'es' ? nameEs : nameEn;

  double? operator [](String nutrient) => per100[nutrient];

  /// This food as the app's meal entity, named in [languageCode].
  MealEntity toMealEntity(String languageCode) => MealEntity(
    code: 'eatpoint:$id',
    name: name(languageCode),
    url: fdcId == null
        ? null
        : 'https://fdc.nal.usda.gov/food-details/$fdcId/nutrients',
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: MealNutrimentsEntity(
      energyKcal100: per100['kcal'],
      carbohydrates100: per100['carbs'],
      fat100: per100['fat'],
      proteins100: per100['protein'],
      sugars100: per100['sugars'],
      saturatedFat100: per100['saturatedFat'],
      fiber100: per100['fibre'],
    ),
    source: MealSourceEntity.fdc,
  );

  static CoreFood? fromJson(Object? json) {
    if (json is! Map) return null;
    final names = json['names'];
    final per100 = json['per100'];
    if (json['id'] is! String || names is! Map || per100 is! Map) return null;
    final values = <String, double>{
      for (final e in per100.entries)
        if (e.key is String && e.value is num)
          e.key as String: (e.value as num).toDouble(),
    };
    if (!values.containsKey('kcal')) return null;
    final source = json['source'];
    return CoreFood(
      id: json['id'] as String,
      conceptId: json['concept'] as String? ?? '',
      nameEs: '${names['es'] ?? ''}',
      nameEn: '${names['en'] ?? ''}',
      tags: {
        if (json['tags'] is List)
          for (final t in json['tags'] as List)
            if (t is String) t,
      },
      per100: values,
      fdcId: source is Map && source['fdc_id'] is int
          ? source['fdc_id'] as int
          : null,
    );
  }
}

/// The catalogue of everyday foods, read from
/// `assets/data/food_knowledge.json`, and the lookup from a food's name to
/// its concept.
class FoodKnowledge {
  static const assetPath = 'assets/data/food_knowledge.json';

  final List<FoodConcept> concepts;

  /// Foods with full nutrition.
  final List<CoreFood> foods;

  late final Map<String, FoodConcept> _byId = {
    for (final c in concepts) c.id: c,
  };

  FoodConcept? conceptById(String id) => _byId[id];

  /// The concept of [food], with the food's own extra tags added.
  Set<String> tagsOf(CoreFood food) => {
    ...?_byId[food.conceptId]?.tags,
    ...food.tags,
  };

  /// Every name of every concept, longest first, so "pechuga de pavo" wins
  /// over "pavo" and "atun en lata" over "atun".
  late final List<({String name, FoodConcept concept})> _names = [
    for (final c in concepts)
      for (final n in {...c.namesEs, ...c.namesEn}) (name: n, concept: c),
  ]..sort((a, b) => b.name.length.compareTo(a.name.length));

  final Map<String, FoodConcept?> _cache = {};

  FoodKnowledge(this.concepts, [this.foods = const []]);

  static FoodKnowledge? _instance;
  static Future<FoodKnowledge>? _loading;
  static final _log = Logger('FoodKnowledge');

  /// The catalogue once [load] has finished, else null.
  static FoodKnowledge? get instance => _instance;

  /// Loads the bundled catalogue once. Safe to call many times.
  static Future<FoodKnowledge> load([AssetBundle? bundle]) {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    return _loading ??= () async {
      try {
        final raw = await (bundle ?? rootBundle).loadString(assetPath);
        return _instance = FoodKnowledge.parse(raw);
      } catch (e) {
        _log.warning('Food knowledge unavailable: $e');
        return _instance = FoodKnowledge(const []);
      }
    }();
  }

  /// For tests.
  static void setInstance(FoodKnowledge? knowledge) {
    _instance = knowledge;
    _loading = null;
  }

  static FoodKnowledge parse(String raw) {
    final decoded = jsonDecode(raw);
    final list = decoded is Map ? decoded['concepts'] : null;
    final foods = decoded is Map ? decoded['foods'] : null;
    return FoodKnowledge(
      [
        if (list is List)
          for (final c in list) ?FoodConcept.fromJson(c),
      ],
      [
        if (foods is List)
          for (final f in foods) ?CoreFood.fromJson(f),
      ],
    );
  }

  /// Lower case, no accents, single spaces, letters and digits only.
  static String fold(String s) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    final buffer = StringBuffer();
    for (final ch in s.toLowerCase().runes) {
      final c = String.fromCharCode(ch);
      final i = from.indexOf(c);
      buffer.write(i >= 0 ? to[i] : c);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// The core food called [foodName] or, failing that, the first core food
  /// of the concept [foodName] matches. Null when neither is known.
  CoreFood? matchFood(String foodName) {
    final key = fold(foodName);
    if (key.isEmpty) return null;
    for (final f in foods) {
      if (fold(f.nameEs) == key || fold(f.nameEn) == key) return f;
    }
    final concept = match(foodName);
    if (concept == null) return null;
    final candidates = foods.where((f) => f.conceptId == concept.id).toList();
    if (candidates.isEmpty) return null;
    // "arroz integral" should find brown rice, plain "arroz" white rice.
    final wantsWholegrain = RegExp(
      r'\b(integral|integrales|wholegrain|wholemeal|wholewheat|brown)\b',
    ).hasMatch(key);
    final preferred = candidates
        .where((f) => f.tags.contains('wholegrain') == wantsWholegrain)
        .toList();
    if (preferred.isNotEmpty) return preferred.first;
    return candidates.first;
  }

  /// The concept a food called [foodName] is, matching its names as whole
  /// words (a plural "s"/"es" allowed). Null when none matches.
  FoodConcept? match(String foodName) {
    final key = fold(foodName);
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) return _cache[key];
    FoodConcept? found;
    for (final entry in _names) {
      final pattern = RegExp('(^| )${RegExp.escape(entry.name)}(e?s)?( |\$)');
      if (pattern.hasMatch(key)) {
        found = entry.concept;
        break;
      }
    }
    return _cache[key] = found;
  }
}
