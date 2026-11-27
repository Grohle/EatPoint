import 'dart:math' as math;

import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';

/// What the user eats, for the generator.
enum DietStyle { omnivore, pescatarian, vegetarian, vegan }

/// The part a food plays in a meal.
enum GenRole { protein, starch, legume, veg, fruit, dairy, fat, nuts, grain }

/// The kind of protein a main meal is built around, rotated over the week.
enum ProteinKind {
  oilyFish,
  whiteFish,
  legume,
  egg,
  poultry,
  redMeat,
  pork,
  tofu,
}

/// A food the generator can use: one of the user's own or one of
/// EatPoint's core foods.
class GenFood {
  final MealEntity meal;
  final Set<String> tags;
  final String? conceptId;

  /// One of the user's foods (logged, saved or a recipe).
  final bool own;

  const GenFood({
    required this.meal,
    required this.tags,
    this.conceptId,
    this.own = false,
  });

  String get name => meal.name ?? '';

  /// The same food under another name (its free-from version).
  GenFood renamed(String newName) => newName == name
      ? this
      : GenFood(
          meal: meal.withName(newName),
          tags: tags,
          conceptId: conceptId,
          own: own,
        );

  bool has(String tag) => tags.contains(tag);

  /// Builds a [GenFood] for [meal], reading its kind from the catalogue,
  /// or from its macros when the catalogue does not know it.
  static GenFood of(
    MealEntity meal, {
    required FoodKnowledge knowledge,
    bool own = false,
  }) {
    final core = knowledge.matchFood(meal.name ?? '');
    final concept = core == null
        ? knowledge.match(meal.name ?? '')
        : knowledge.conceptById(core.conceptId);
    final tags = <String>{...?concept?.tags, if (core != null) ...core.tags};
    if (concept == null) tags.addAll(_tagsFromMacros(meal));
    return GenFood(meal: meal, tags: tags, conceptId: concept?.id, own: own);
  }

  static Set<String> _tagsFromMacros(MealEntity meal) {
    final profile = meal.nutriments.pointsProfile;
    final kcal = meal.nutriments.energyKcal100 ?? 0;
    if (profile == null) return const {};
    if (profile.proteinShare >= 0.45) return {'protein'};
    if (profile.fatShare >= 0.7) return {'fat'};
    if (kcal < 60 && profile.carbShare >= 0.5) return {'veg'};
    if (profile.carbShare >= 0.6 && kcal >= 120) return {'carb'};
    return const {};
  }
}

class MenuGeneratorOptions {
  final List<DateTime> days;
  final DietStyle diet;

  /// Words of foods the user does not want ("cerdo", "pescado", "lactosa").
  final List<String> excluded;

  /// Choose the user's own foods first when they fit.
  final bool preferOwn;
  final int seed;

  /// The user's diet profile: leaves out what it rules out, uses free-from
  /// versions where they exist, and suggests the foods the user likes. Its
  /// diet style wins over [diet].
  final DietChecker? checker;

  /// Language of the free-from names ("sin lactosa", "lactose-free").
  final String languageCode;

  const MenuGeneratorOptions({
    required this.days,
    this.diet = DietStyle.omnivore,
    this.excluded = const [],
    this.preferOwn = true,
    this.seed = 1,
    this.checker,
    this.languageCode = 'en',
  });

  DietStyle get effectiveDiet => checker?.profile.diet ?? diet;
}

/// A generated week: the menu (as the importer reads it, so it goes through
/// the same review screen) and the foods it names.
class GeneratedMenu {
  final ImportedMenu menu;

  /// Every food the menu names, by name.
  final Map<String, GenFood> foods;

  const GeneratedMenu(this.menu, this.foods);
}

/// Builds a varied week of menus for the user's meals from their own foods
/// and EatPoint's core foods.
///
/// Main meals rotate their protein over the week to a pattern of general
/// guides (oily fish twice, white fish, pulses three times, eggs, poultry,
/// red meat at most once), adapted to the diet style. Each meal gets its
/// parts (protein, starch, vegetables and oil for a main meal; grain, milk
/// or yogurt and fruit for breakfast; fruit and yogurt or nuts for a snack)
/// with fixed household amounts for vegetables, fruit, oil and nuts. The
/// protein, starch and grain are left without an amount so the review fits
/// them to each meal's points.
class MenuGenerator {
  MenuGenerator._();

  static const vegGrams = 150.0;
  static const saladGrams = 100.0;
  static const oilGrams = 10.0;
  static const breadOilGrams = 5.0;
  static const nutsGrams = 20.0;
  static const milkMl = 250.0;
  static const yogurtGrams = 125.0;

  /// The week's protein pattern for 14 main meals, per diet style.
  static const _pattern = <DietStyle, Map<ProteinKind, int>>{
    DietStyle.omnivore: {
      ProteinKind.oilyFish: 2,
      ProteinKind.whiteFish: 2,
      ProteinKind.legume: 3,
      ProteinKind.egg: 2,
      ProteinKind.poultry: 3,
      ProteinKind.redMeat: 1,
      ProteinKind.pork: 1,
    },
    DietStyle.pescatarian: {
      ProteinKind.oilyFish: 3,
      ProteinKind.whiteFish: 3,
      ProteinKind.legume: 4,
      ProteinKind.egg: 3,
      ProteinKind.tofu: 1,
    },
    DietStyle.vegetarian: {
      ProteinKind.legume: 6,
      ProteinKind.egg: 4,
      ProteinKind.tofu: 4,
    },
    DietStyle.vegan: {ProteinKind.legume: 8, ProteinKind.tofu: 6},
  };

  static GeneratedMenu generate({
    required List<MealSlot> slots,
    required String Function(MealSlot) nameOf,
    required List<GenFood> pool,
    required MenuGeneratorOptions options,
  }) {
    final random = math.Random(options.seed);
    final checker = options.checker;
    final usable = [
      for (final f in pool)
        if (_allowed(f, options) &&
            !(checker?.blocks(f.name, conceptId: f.conceptId) ?? false))
          checker == null
              ? f
              : f.renamed(
                  checker.adaptedName(
                    f.name,
                    options.languageCode,
                    conceptId: f.conceptId,
                  ),
                ),
    ];
    final uses = <String, int>{};
    final named = <String, GenFood>{};

    GenFood? pick(bool Function(GenFood) where, {bool preferOwn = true}) {
      final candidates = usable.where(where).toList();
      if (candidates.isEmpty) return null;
      final own = candidates.where((f) => f.own).toList();
      // Foods the user likes come up more often, as long as they are not
      // used more than the others.
      final liked = checker == null
          ? const <GenFood>[]
          : candidates.where((f) => checker.isLiked(f.name)).toList();
      final leastUse = candidates
          .map((f) => uses[f.name] ?? 0)
          .reduce(math.min);
      final likedFresh = liked
          .where((f) => (uses[f.name] ?? 0) <= leastUse + 1)
          .toList();
      final from = likedFresh.isNotEmpty && random.nextDouble() < 0.75
          ? likedFresh
          : options.preferOwn &&
                preferOwn &&
                own.isNotEmpty &&
                random.nextDouble() < 0.7
          ? own
          : candidates;
      // Least used first, then at random among equals.
      from.shuffle(random);
      from.sort((a, b) => (uses[a.name] ?? 0).compareTo(uses[b.name] ?? 0));
      final chosen = from.first;
      uses[chosen.name] = (uses[chosen.name] ?? 0) + 1;
      named[chosen.name] = chosen;
      return chosen;
    }

    ImportedFood food(GenFood f, [double? grams]) => ImportedFood(
      name: f.name,
      amount: grams,
      unit: grams == null ? null : (f.meal.isLiquid ? 'ml' : 'g'),
    );

    double portionGrams(GenFood f, double fallback) {
      final concept = FoodKnowledge.instance?.conceptById(f.conceptId ?? '');
      final portion = concept?.mainPortion;
      if (portion == null) return fallback;
      // A piece of fruit; half of a big one (a mango, a slice of melon);
      // small units (strawberries, cherries) by weight.
      if (portion.grams < 40) return fallback;
      return portion.grams > 250 ? portion.grams / 2 : portion.grams;
    }

    // Main meals of the week, in order, and their protein kinds.
    final mainSlots = slots.where(_isMain).toList();
    final mainCount = mainSlots.length * options.days.length;
    final kinds = _proteinSchedule(
      _pattern[options.effectiveDiet]!,
      mainCount,
      random,
      available: {
        for (final k in ProteinKind.values)
          if (usable.any((f) => _isProteinKind(f, k))) k,
      },
    );
    var mainIndex = 0;
    var snackIndex = 0;

    final days = <ImportedDay>[];
    for (final date in options.days) {
      final meals = <ImportedMeal>[];
      for (final slot in slots) {
        final foods = <ImportedFood>[];
        if (_isMain(slot)) {
          final kind = kinds.isEmpty ? null : kinds[mainIndex % kinds.length];
          mainIndex++;
          final protein = kind == null
              ? pick((f) => f.has('protein') && !f.has('dairy'))
              : pick((f) => _isProteinKind(f, kind));
          if (protein != null) foods.add(food(protein));
          if (kind != ProteinKind.legume) {
            final wholegrain = random.nextDouble() < 0.65;
            final starch =
                pick(
                  (f) => _isStarch(f) && f.has('wholegrain') == wholegrain,
                ) ??
                pick(_isStarch);
            if (starch != null) foods.add(food(starch));
          }
          final veg = pick(
            (f) => f.has('veg') && !f.has('legume') && !f.has('carb'),
          );
          if (veg != null) {
            foods.add(
              food(veg, veg.conceptId == 'lettuce' ? saladGrams : vegGrams),
            );
          }
          final oil = pick((f) => f.conceptId == 'olive_oil', preferOwn: false);
          if (oil != null) foods.add(food(oil, oilGrams));
        } else if (slot.baseType == IntakeTypeEntity.breakfast) {
          final grain = pick(
            (f) =>
                f.conceptId == 'bread_slice' ||
                f.conceptId == 'oats' ||
                f.conceptId == 'baguette' ||
                f.conceptId == 'rice_cake',
          );
          if (grain != null) foods.add(food(grain));
          final drink = pick(
            (f) => options.effectiveDiet == DietStyle.vegan
                ? f.conceptId == 'plant_milk'
                : f.conceptId == 'milk' || f.conceptId == 'yogurt',
          );
          if (drink != null) {
            foods.add(
              food(drink, drink.conceptId == 'yogurt' ? yogurtGrams : milkMl),
            );
          }
          // The fat of breakfast, left to fit the meal's fat points: oil
          // (or avocado) on bread, nuts or seeds with oats, peanut butter on
          // rice cakes.
          final bread =
              grain != null &&
              (grain.conceptId == 'bread_slice' ||
                  grain.conceptId == 'baguette');
          final fat = bread
              ? pick(
                  (f) => f.conceptId == 'olive_oil' || f.conceptId == 'avocado',
                  preferOwn: false,
                )
              : grain?.conceptId == 'rice_cake'
              ? pick((f) => f.conceptId == 'peanut_butter')
              : pick((f) => f.has('nuts') && f.conceptId != 'peanut_butter');
          if (fat != null) {
            // Nuts by the handful; oil, avocado and peanut butter fit.
            foods.add(
              food(
                fat,
                fat.has('nuts') && fat.conceptId != 'peanut_butter'
                    ? nutsGrams + 5
                    : null,
              ),
            );
          }
          if (bread && random.nextBool()) {
            final tomato = pick((f) => f.conceptId == 'tomato');
            if (tomato != null) foods.add(food(tomato, 60));
          }
          final fruit = pick((f) => f.has('fruit') && !f.has('fat'));
          if (fruit != null) foods.add(food(fruit, portionGrams(fruit, 120)));
        } else {
          // Snack: a sandwich, or fruit with yogurt and nuts, alternating;
          // the bread, filling, yogurt and nuts fit the meal's points.
          final sandwich = (snackIndex++).isOdd;
          if (sandwich) {
            final bread = pick(
              (f) => f.conceptId == 'bread_slice' || f.conceptId == 'baguette',
            );
            if (bread != null) foods.add(food(bread));
            final filling = pick(
              (f) => options.effectiveDiet == DietStyle.vegan
                  ? f.conceptId == 'chickpeas' && f.name.contains('ummus') ||
                        f.conceptId == 'peanut_butter'
                  : f.conceptId == 'turkey_breast' ||
                        f.conceptId == 'ham' ||
                        f.conceptId == 'cheese_slice' ||
                        f.conceptId == 'fresh_cheese' ||
                        f.conceptId == 'tuna_can',
            );
            if (filling != null) foods.add(food(filling));
            final tomato = pick((f) => f.conceptId == 'tomato');
            if (tomato != null) foods.add(food(tomato, 60));
          } else {
            final fruit = pick((f) => f.has('fruit') && !f.has('fat'));
            if (fruit != null) foods.add(food(fruit, portionGrams(fruit, 120)));
            final dairy = options.effectiveDiet == DietStyle.vegan
                ? pick((f) => f.conceptId == 'plant_milk')
                : pick((f) => f.conceptId == 'yogurt');
            if (dairy != null) {
              foods.add(
                food(dairy, dairy.conceptId == 'yogurt' ? yogurtGrams : milkMl),
              );
            }
            // Oats fill the rest of the snack's points.
            final oats = pick((f) => f.conceptId == 'oats');
            if (oats != null) foods.add(food(oats));
            final nuts = pick(
              (f) => f.has('nuts') && f.conceptId != 'peanut_butter',
            );
            if (nuts != null) foods.add(food(nuts, nutsGrams));
          }
        }
        if (foods.isNotEmpty) {
          meals.add(ImportedMeal(label: nameOf(slot), foods: foods));
        }
      }
      days.add(ImportedDay(date: date, meals: meals));
    }
    return GeneratedMenu(ImportedMenu(days), named);
  }

  static bool _isMain(MealSlot slot) =>
      slot.baseType == IntakeTypeEntity.lunch ||
      slot.baseType == IntakeTypeEntity.dinner;

  static bool _isStarch(GenFood f) =>
      f.has('carb') &&
      !f.has('legume') &&
      !f.has('sweet') &&
      !f.has('fruit') &&
      !f.has('veg') &&
      f.conceptId != 'rice_cake' &&
      f.conceptId != 'biscuit' &&
      f.conceptId != 'oats';

  static bool _isProteinKind(GenFood f, ProteinKind kind) {
    switch (kind) {
      case ProteinKind.oilyFish:
        return f.has('oily_fish');
      case ProteinKind.whiteFish:
        return f.has('fish') && !f.has('oily_fish');
      case ProteinKind.legume:
        return f.has('legume') && f.conceptId != 'peas';
      case ProteinKind.egg:
        return f.conceptId == 'egg';
      case ProteinKind.poultry:
        return f.conceptId == 'chicken_breast' ||
            f.conceptId == 'chicken_thigh' ||
            f.conceptId == 'turkey_breast';
      case ProteinKind.redMeat:
        return f.conceptId == 'beef_steak' || f.conceptId == 'minced_meat';
      case ProteinKind.pork:
        return f.conceptId == 'pork_loin';
      case ProteinKind.tofu:
        return f.conceptId == 'tofu';
    }
  }

  /// Foods the diet and the exclusions allow.
  static bool _allowed(GenFood f, MenuGeneratorOptions o) {
    final name = FoodKnowledge.fold(f.name);
    for (final word in o.excluded) {
      final w = FoodKnowledge.fold(word);
      if (w.isNotEmpty && name.contains(w)) return false;
    }
    if (f.has('processed_meat') || f.has('sweet')) return false;
    final meat =
        f.has('b12') &&
        f.has('protein') &&
        !f.has('fish') &&
        f.conceptId != 'egg' &&
        !f.has('dairy');
    switch (o.effectiveDiet) {
      case DietStyle.omnivore:
        return true;
      case DietStyle.pescatarian:
        return !meat;
      case DietStyle.vegetarian:
        return !meat && !f.has('fish');
      case DietStyle.vegan:
        return !meat &&
            !f.has('fish') &&
            f.conceptId != 'egg' &&
            !(f.has('dairy') && f.conceptId != 'plant_milk') &&
            f.conceptId != 'honey' &&
            f.conceptId != 'butter';
    }
  }

  /// [count] protein kinds following [pattern] (per 14 meals), shuffled
  /// so the same kind is not served twice in a row. Kinds with no food in
  /// [available] are left out.
  static List<ProteinKind> _proteinSchedule(
    Map<ProteinKind, int> pattern,
    int count,
    math.Random random, {
    required Set<ProteinKind> available,
  }) {
    final usable = {
      for (final e in pattern.entries)
        if (available.contains(e.key)) e.key: e.value,
    };
    if (usable.isEmpty || count == 0) return const [];
    final total = usable.values.fold(0, (a, b) => a + b);
    // Largest-remainder share of [count] meals.
    final ideal = {
      for (final e in usable.entries) e.key: count * e.value / total,
    };
    final counts = {for (final e in ideal.entries) e.key: e.value.floor()};
    var left = count - counts.values.fold(0, (a, b) => a + b);
    final byRemainder = ideal.keys.toList()
      ..sort(
        (a, b) => (ideal[b]! - counts[b]!).compareTo(ideal[a]! - counts[a]!),
      );
    for (final k in byRemainder) {
      if (left <= 0) break;
      counts[k] = counts[k]! + 1;
      left--;
    }
    final list = [
      for (final e in counts.entries) ...List.filled(e.value, e.key),
    ]..shuffle(random);
    // Separate neighbours of the same kind where a swap allows it.
    for (var i = 1; i < list.length; i++) {
      if (list[i] != list[i - 1]) continue;
      for (var j = i + 1; j < list.length; j++) {
        if (list[j] != list[i] &&
            (j + 1 >= list.length || list[j + 1] != list[i]) &&
            list[j - 1] != list[i]) {
          final t = list[i];
          list[i] = list[j];
          list[j] = t;
          break;
        }
      }
    }
    return list;
  }
}
