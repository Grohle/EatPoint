import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';

/// Claims printed on a pack ("vegan", "gluten-free"…).
enum FoodLabel { vegan, vegetarian, glutenFree, lactoseFree, halal, kosher }

/// Where [FoodFacts] came from.
enum FoodFactsSource { label, openFoodFacts }

/// What a packaged food's label (or Open Food Facts) says it contains, may
/// contain and claims: more reliable than its name alone.
class FoodFacts {
  /// Allergens and other traits the food contains.
  final Set<DietTrait> contains;

  /// "May contain traces of…".
  final Set<DietTrait> traces;

  final Set<FoodLabel> labels;

  /// The ingredients list as printed, when known.
  final String? ingredients;

  final FoodFactsSource source;

  const FoodFacts({
    this.contains = const {},
    this.traces = const {},
    this.labels = const {},
    this.ingredients,
    this.source = FoodFactsSource.label,
  });

  bool get isEmpty =>
      contains.isEmpty &&
      traces.isEmpty &&
      labels.isEmpty &&
      (ingredients == null || ingredients!.trim().isEmpty);

  Map<String, dynamic> toJson() => {
    'contains': [for (final t in contains) t.name],
    'traces': [for (final t in traces) t.name],
    'labels': [for (final l in labels) l.name],
    if (ingredients != null) 'ingredients': ingredients,
    'source': source.name,
  };

  factory FoodFacts.fromJson(Object? json) {
    if (json is! Map) return const FoodFacts();
    Set<T> names<T extends Enum>(List<T> values, Object? list) => {
      if (list is List)
        for (final n in list) ?values.where((v) => v.name == n).firstOrNull,
    };
    final ingredients = json['ingredients'];
    return FoodFacts(
      contains: names(DietTrait.values, json['contains']),
      traces: names(DietTrait.values, json['traces']),
      labels: names(FoodLabel.values, json['labels']),
      ingredients: ingredients is String ? ingredients : null,
      source:
          FoodFactsSource.values
              .where((v) => v.name == json['source'])
              .firstOrNull ??
          FoodFactsSource.label,
    );
  }

  /// Open Food Facts' allergen tags (the same for allergens and traces).
  static const _offAllergens = <String, Set<DietTrait>>{
    'en:gluten': {DietTrait.gluten},
    'en:milk': {DietTrait.milk, DietTrait.lactose},
    'en:eggs': {DietTrait.egg},
    'en:fish': {DietTrait.fish},
    'en:crustaceans': {DietTrait.crustacean},
    'en:molluscs': {DietTrait.mollusc},
    'en:peanuts': {DietTrait.peanut},
    'en:nuts': {DietTrait.treeNut},
    'en:soybeans': {DietTrait.soy},
    'en:sesame-seeds': {DietTrait.sesame},
    'en:celery': {DietTrait.celery},
    'en:mustard': {DietTrait.mustard},
    'en:sulphur-dioxide-and-sulphites': {DietTrait.sulphites},
    'en:lupin': {DietTrait.lupin},
  };

  static const _offLabels = <String, FoodLabel>{
    'en:vegan': FoodLabel.vegan,
    'en:vegetarian': FoodLabel.vegetarian,
    'en:gluten-free': FoodLabel.glutenFree,
    'en:no-gluten': FoodLabel.glutenFree,
    'en:lactose-free': FoodLabel.lactoseFree,
    'en:no-lactose': FoodLabel.lactoseFree,
    'en:halal': FoodLabel.halal,
    'en:kosher': FoodLabel.kosher,
  };

  /// From an Open Food Facts product's tags and ingredients.
  factory FoodFacts.fromOpenFoodFacts({
    List<String>? allergens,
    List<String>? traces,
    List<String>? labels,
    List<String>? analysis,
    String? ingredients,
  }) {
    Set<DietTrait> map(List<String>? tags) => {
      for (final t in tags ?? const <String>[]) ...?_offAllergens[t],
    };
    final contains = map(allergens);
    final text = ingredients?.trim();
    if (text != null && text.isNotEmpty) {
      contains.addAll(traitsInText(text));
    }
    final claims = <FoodLabel>{
      for (final t in labels ?? const <String>[]) ?_offLabels[t],
      if (analysis?.contains('en:vegan') ?? false) FoodLabel.vegan,
      if (analysis?.contains('en:vegetarian') ?? false) FoodLabel.vegetarian,
    };
    return FoodFacts(
      contains: contains,
      traces: map(traces),
      labels: claims,
      ingredients: text == null || text.isEmpty ? null : text,
      source: FoodFactsSource.openFoodFacts,
    );
  }

  /// Traits found in an ingredients list. Words that only describe what a
  /// food is free of ("sin gluten") do not count, and names of whole
  /// dishes are not guessed from, so a cut like "lomo" alone means nothing
  /// here.
  static Set<DietTrait> traitsInText(String text) {
    final folded = FoodKnowledge.fold(text);
    final traits = <DietTrait>{};
    // Each ingredient on its own, so "leche de coco" is not milk and "sin
    // gluten" is not gluten.
    for (final part in folded.split(RegExp(r'[,;:()\[\]\n.]'))) {
      final p = part.trim();
      if (p.isEmpty) continue;
      traits.addAll(DietChecker.traitsOf(p, conceptId: ''));
    }
    return traits;
  }
}

/// Reads the ingredients and allergen statements from the text of a photo
/// of a food label, in Spanish or English.
class IngredientLabelParser {
  IngredientLabelParser._();

  static final _ingredientsHead = RegExp(
    r'(ingredientes|ingredients|ingredienti|zutaten|ingr[eé]dients)\s*:?',
    caseSensitive: false,
  );
  static final _containsHead = RegExp(
    r'\b(contiene|contains|alergenos|allergens|al[eé]rgenos|contient|allerg[eè]nes|enth[aä]lt|allergene|allergeni)\s*:?',
    caseSensitive: false,
  );
  static final _tracesHead = RegExp(
    r'(puede contener( trazas de)?|trazas de|may contain( traces of)?|traces of|peut contenir( des traces de?)?|traces [ée]ventuelles de|kann spuren( von)?( enthalten)?|spuren von|pu[oò] contenere( tracce di)?|tracce di|elaborado en (una )?(f[aá]brica|instalaci[oó]n) que (tambi[eé]n )?(utiliza|procesa|manipula)|produced in a factory (that|which) (also )?(handles|uses))\s*:?',
    caseSensitive: false,
  );

  static final _labelWords = <FoodLabel, RegExp>{
    FoodLabel.vegan: RegExp(
      r'\b(vegan[oa]?s?|vegane?|v[ée]g[ée]talien|apto para veganos|plant[- ]based)\b',
    ),
    FoodLabel.vegetarian: RegExp(
      r'\b(vegetarian[oa]?[si]?|vegetarisch|v[ée]g[ée]tarien(ne)?|apto para vegetarianos)\b',
    ),
    FoodLabel.glutenFree: RegExp(
      r'\b(sin gluten|gluten[ -]free|sans gluten|glutenfrei|senza glutine)\b',
    ),
    FoodLabel.lactoseFree: RegExp(
      r'\b(sin lactosa|lactose[ -]free|sans lactose|laktosefrei|senza lattosio)\b',
    ),
    FoodLabel.halal: RegExp(r'\bhalal\b'),
    FoodLabel.kosher: RegExp(r'\bkosher\b'),
  };

  /// Facts from [text]; empty when nothing on the label speaks to them.
  static FoodFacts parse(String text) {
    final folded = FoodKnowledge.fold(text);
    final labels = <FoodLabel>{
      for (final e in _labelWords.entries)
        if (e.value.hasMatch(folded)) e.key,
    };

    final traceMatch = _tracesHead.firstMatch(text);
    final tracesText = traceMatch == null
        ? ''
        : _sentence(text.substring(traceMatch.end));
    final bodyEnd = traceMatch?.start ?? text.length;
    final head = _ingredientsHead.firstMatch(text);
    final ingredients = head == null
        ? null
        : text.substring(head.end, bodyEnd).trim();

    final contains = <DietTrait>{};
    if (ingredients != null && ingredients.isNotEmpty) {
      contains.addAll(FoodFacts.traitsInText(ingredients));
    }
    for (final m in _containsHead.allMatches(text)) {
      if (traceMatch != null && m.start >= traceMatch.start) continue;
      contains.addAll(FoodFacts.traitsInText(_sentence(text.substring(m.end))));
    }
    // A claim on the pack wins over a word that only looked like it.
    if (labels.contains(FoodLabel.glutenFree)) {
      contains.remove(DietTrait.gluten);
    }
    if (labels.contains(FoodLabel.lactoseFree)) {
      contains.removeAll({DietTrait.lactose, DietTrait.lowLactose});
    }
    final traces = FoodFacts.traitsInText(tracesText)
      ..removeAll(contains)
      // Only allergens make sense as traces.
      ..removeAll({
        DietTrait.meat,
        DietTrait.pork,
        DietTrait.beef,
        DietTrait.alcohol,
        DietTrait.honey,
        DietTrait.gelatin,
        DietTrait.lactose,
        DietTrait.lowLactose,
      });
    return FoodFacts(
      contains: contains,
      traces: traces,
      labels: labels,
      ingredients: ingredients == null || ingredients.isEmpty
          ? null
          : ingredients.replaceAll(RegExp(r'\s+'), ' '),
    );
  }

  /// Text up to the end of its sentence.
  static String _sentence(String text) {
    final end = RegExp(r'\.(\s|$)').firstMatch(text);
    return end == null ? text : text.substring(0, end.start);
  }
}
