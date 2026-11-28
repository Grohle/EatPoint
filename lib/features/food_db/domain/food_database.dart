import 'dart:convert';
import 'dart:io';

import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/food_facts.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';

/// Where a food of the downloadable database comes from.
class FoodDbSource {
  final String id;
  final String name;
  final String license;
  final String url;

  const FoodDbSource({
    required this.id,
    required this.name,
    required this.license,
    required this.url,
  });

  static FoodDbSource? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    return FoodDbSource(
      id: id,
      name: name,
      license: json['license'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}

/// One food of the downloadable database, values per 100 g (or 100 ml).
class FoodDbEntry {
  final String id;
  final String source;
  final String? nameEs;
  final String? nameEn;
  final String? brand;
  final double kcal;

  /// Available carbohydrates, without fibre.
  final double carbs;
  final double protein;
  final double fat;
  final double? fibre;
  final double? sugars;
  final double? saturatedFat;
  final double? salt;
  final double? servingGrams;
  final bool liquid;
  final String? category;
  final Set<DietTrait> allergens;
  final Set<DietTrait> traces;
  final Set<FoodLabel> labels;

  /// EatPoint: the food's own household unit ("tortilla", 40 g), reviewed
  /// by name; known with no portion when the food has none (a drink, a
  /// sauce). Unknown means the generic catalogue decides.
  final ({bool known, FoodPortion? portion}) unit;

  /// The name folded for search, in both languages.
  final String searchText;

  FoodDbEntry({
    required this.id,
    required this.source,
    this.nameEs,
    this.nameEn,
    this.brand,
    required this.kcal,
    required this.carbs,
    required this.protein,
    required this.fat,
    this.fibre,
    this.sugars,
    this.saturatedFat,
    this.salt,
    this.servingGrams,
    this.liquid = false,
    this.category,
    this.allergens = const {},
    this.traces = const {},
    this.labels = const {},
    this.unit = (known: false, portion: null),
  }) : searchText = FoodKnowledge.fold(
         [nameEs, nameEn, brand].whereType<String>().join(' | '),
       );

  /// The name in [languageCode], or the other one.
  String name(String languageCode) {
    final preferred = languageCode == 'es' ? nameEs : nameEn;
    return preferred ?? nameEs ?? nameEn ?? id;
  }

  /// The barcode, for supermarket products.
  String? get barcode => id.startsWith('o:') ? id.substring(2) : null;

  /// The code a meal made from this food carries.
  String get code => barcode ?? 'eatpoint-db:$id';

  /// Allergens, traces and claims, for the diet check.
  FoodFacts? get facts => allergens.isEmpty && traces.isEmpty && labels.isEmpty
      ? null
      : FoodFacts(
          contains: {
            ...allergens,
            if (allergens.contains(DietTrait.milk)) DietTrait.lactose,
          },
          traces: traces,
          labels: labels,
          source: FoodFactsSource.openFoodFacts,
        );

  MealEntity toMealEntity(String languageCode) {
    final unit = liquid ? 'ml' : 'g';
    return MealEntity(
      code: code,
      name: name(languageCode),
      brands: brand,
      url: switch (barcode) {
        final b? => 'https://world.openfoodfacts.org/product/$b',
        null when id.startsWith('u:') =>
          'https://fdc.nal.usda.gov/food-details/${id.substring(2)}/nutrients',
        null => null,
      },
      mealQuantity: null,
      mealUnit: unit,
      servingQuantity: servingGrams,
      servingUnit: unit,
      servingSize: servingGrams == null
          ? null
          : '${servingGrams!.round()} $unit',
      nutriments: MealNutrimentsEntity(
        energyKcal100: kcal,
        carbohydrates100: carbs,
        fat100: fat,
        proteins100: protein,
        sugars100: sugars,
        saturatedFat100: saturatedFat,
        fiber100: fibre,
      ),
      source: switch (source) {
        'off' => MealSourceEntity.off,
        'usda' => MealSourceEntity.fdc,
        _ => MealSourceEntity.custom,
      },
    );
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : null;

  static Set<DietTrait> _traits(Object? list) => {
    if (list is List)
      for (final n in list)
        ?DietTrait.values.where((t) => t.name == n).firstOrNull,
  };

  static FoodDbEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['i'];
    final kcal = _num(json['k']);
    final carbs = _num(json['c']);
    final protein = _num(json['p']);
    final fat = _num(json['f']);
    if (id is! String ||
        kcal == null ||
        carbs == null ||
        protein == null ||
        fat == null) {
      return null;
    }
    final es = json['es'];
    final en = json['en'];
    if (es is! String? || en is! String? || (es == null && en == null)) {
      return null;
    }
    final labels = json['lb'];
    final rawUnit = json['u'];
    final unit = rawUnit == 0
        ? (known: true, portion: null)
        : rawUnit is Map
        ? (
            known: true,
            portion: FoodPortion.fromJson({
              'unit': 'piece',
              'es': rawUnit['es'],
              'en': rawUnit['en'],
              'grams': rawUnit['g'],
              'default': true,
            }),
          )
        : (known: false, portion: null);
    return FoodDbEntry(
      unit: unit,
      id: id,
      source: json['s'] as String? ?? '',
      nameEs: es,
      nameEn: en,
      brand: json['b'] as String?,
      kcal: kcal,
      carbs: carbs,
      protein: protein,
      fat: fat,
      fibre: _num(json['fi']),
      sugars: _num(json['su']),
      saturatedFat: _num(json['sf']),
      salt: _num(json['sa']),
      servingGrams: _num(json['sv']),
      liquid: json['l'] == 1,
      category: json['cat'] as String?,
      allergens: _traits(json['a']),
      traces: _traits(json['t']),
      labels: {
        if (labels is List)
          for (final n in labels)
            ?FoodLabel.values.where((l) => l.name == n).firstOrNull,
      },
    );
  }
}

/// EatPoint's downloadable food database, held in memory once loaded.
class FoodDatabase {
  final int version;
  final String? generated;
  final List<FoodDbSource> sources;
  final List<FoodDbEntry> foods;
  late final Map<String, FoodDbEntry> _byCode = {
    for (final f in foods) f.code: f,
  };

  FoodDatabase({
    required this.version,
    this.generated,
    this.sources = const [],
    required this.foods,
  });

  static FoodDatabase? _instance;

  /// The loaded database, or null when none is downloaded.
  static FoodDatabase? get instance => _instance;
  static void setInstance(FoodDatabase? db) => _instance = db;

  /// Reads the gzip-compressed JSON written by `tool/food_db/build_db.py`.
  static FoodDatabase parseGzip(List<int> bytes) =>
      parse(utf8.decode(gzip.decode(bytes)));

  static FoodDatabase parse(String text) {
    final json = jsonDecode(text);
    if (json is! Map || json['format'] != 'eatpoint-foods') {
      throw const FormatException('Not an EatPoint food database');
    }
    return FoodDatabase(
      version: (json['version'] as num?)?.toInt() ?? 0,
      generated: json['generated'] as String?,
      sources: [
        for (final s in json['sources'] as List? ?? const [])
          ?FoodDbSource.fromJson(s),
      ],
      foods: [
        for (final f in json['foods'] as List? ?? const [])
          ?FoodDbEntry.fromJson(f),
      ],
    );
  }

  FoodDbEntry? byCode(String? code) => code == null ? null : _byCode[code];

  /// Foods whose name (in either language, or brand) has every word of
  /// [query] as the start of a word; names that start with the query and
  /// shorter names first, EatPoint's own list before the others.
  List<FoodDbEntry> search(
    String query, {
    String languageCode = 'en',
    int limit = 30,
  }) {
    final q = FoodKnowledge.fold(query).trim();
    if (q.length < 2) return const [];
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final patterns = [
      for (final w in words) RegExp('(^|[^a-z0-9])${RegExp.escape(w)}'),
    ];
    final scored = <(FoodDbEntry, double)>[];
    for (final f in foods) {
      final text = f.searchText;
      if (!patterns.every((p) => p.hasMatch(text))) continue;
      final name = FoodKnowledge.fold(f.name(languageCode));
      var score = 0.0;
      if (name == q) {
        score += 100;
      } else if (name.startsWith(q)) {
        score += 50;
      }
      // Prefer names in the user's language and short, plain names.
      if ((languageCode == 'es' ? f.nameEs : f.nameEn) != null) score += 20;
      score -= name.length / 10;
      score += switch (f.source) {
        'eatpoint' => 15,
        'usda' => 5,
        _ => 0,
      };
      scored.add((f, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (f, _) in scored.take(limit)) f];
  }

  /// The single best food for [name], or null when nothing matches well.
  FoodDbEntry? bestMatch(String name, {String languageCode = 'en'}) {
    final hits = search(name, languageCode: languageCode, limit: 1);
    return hits.firstOrNull;
  }
}
