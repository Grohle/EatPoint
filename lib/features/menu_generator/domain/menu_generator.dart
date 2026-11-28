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

  /// EatPoint: an efficient shopping basket. Fewer different products
  /// (the same few vegetables, starches and fruit, one food per kind of
  /// protein), fish and meat early in each week and the longer-lasting
  /// proteins later, and every other day's lunch made from the previous
  /// dinner's leftovers. The week's protein pattern is kept.
  final bool efficient;

  /// The other people the menu is also for (their diet style and
  /// profile). Foods all of them can eat come first, so most dishes are
  /// shared; what one of them can't have is swapped for them afterwards.
  final List<MenuCompanion> companions;

  /// The note on a meal made from leftovers ("Leftovers from dinner").
  final String? leftoversLabel;

  /// EatPoint: foods the user always has in a meal (milk at breakfast,
  /// bread every morning), by meal id. They take the place of what the
  /// generator would choose for the same part of the meal, or are added.
  final Map<String, List<FixedFood>> fixed;

  const MenuGeneratorOptions({
    required this.days,
    this.diet = DietStyle.omnivore,
    this.excluded = const [],
    this.preferOwn = true,
    this.seed = 1,
    this.checker,
    this.languageCode = 'en',
    this.efficient = false,
    this.companions = const [],
    this.leftoversLabel,
    this.fixed = const {},
  });

  DietStyle get effectiveDiet => checker?.profile.diet ?? diet;
}

/// A food the user always has in a meal, and how much of it.
class FixedFood {
  final GenFood food;
  final double grams;

  const FixedFood(this.food, this.grams);
}

/// Someone else the menu is also for.
class MenuCompanion {
  final DietStyle diet;
  final DietChecker? checker;

  const MenuCompanion({this.diet = DietStyle.omnivore, this.checker});

  /// Whether they can eat [f] as it is.
  bool canEat(GenFood f) =>
      MenuGenerator.allowedFor(f, diet) &&
      !(checker?.blocks(f.name, conceptId: f.conceptId) ?? false);
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

    // Efficient basket: how many different foods each part of the menu
    // uses over a week, and the ones used so far.
    final weeks = math.max(1, (options.days.length / 7).ceil());
    const groupLimits = {
      'veg': 3,
      'starch': 2,
      'fruit': 3,
      'grain': 1,
      'breakfast-drink': 1,
      'breakfast-fat': 2,
      'nuts': 1,
      'filling': 2,
      'snack-dairy': 1,
    };
    final groupFoods = <String, Set<String>>{};
    // The foods of the meal before, not repeated in the next one when
    // another fits.
    var previousMeal = <String>{};
    // EatPoint: the foods of each day so far, so none comes back the same
    // day or the next (oil aside), and the user's fixed foods of the meal
    // being planned.
    final dayFoods = <Set<String>>[];
    var slotFixed = <FixedFood>[];
    final fixedGrams = <String, double>{};
    // The user's fixed foods come every day, so they are always "fresh".
    var checkingFixed = false;
    bool fresh(GenFood f) =>
        checkingFixed ||
        !(dayFoods.isNotEmpty && dayFoods.last.contains(f.name)) &&
            !(dayFoods.length > 1 &&
                dayFoods[dayFoods.length - 2].contains(f.name));

    GenFood? pick(
      bool Function(GenFood) where, {
      bool preferOwn = true,
      String? group,
      bool varied = true,
    }) {
      // The user's own choice for this part of the meal comes first.
      for (final fx in slotFixed) {
        checkingFixed = true;
        final fits = where(fx.food);
        checkingFixed = false;
        if (fits) {
          slotFixed = [...slotFixed]..remove(fx);
          named[fx.food.name] = fx.food;
          fixedGrams[fx.food.name] = fx.grams;
          uses[fx.food.name] = (uses[fx.food.name] ?? 0) + 1;
          return fx.food;
        }
      }
      var candidates = usable.where(where).toList();
      if (candidates.isEmpty) return null;
      // Shared meals: foods everyone at the table can eat first.
      if (options.companions.isNotEmpty) {
        final shared = candidates
            .where((f) => options.companions.every((c) => c.canEat(f)))
            .toList();
        if (shared.isNotEmpty) candidates = shared;
      }
      if (options.efficient && group != null) {
        final used = groupFoods.putIfAbsent(group, () => {});
        final limit = group.startsWith('protein:')
            ? weeks
            : (groupLimits[group] ?? 2) * weeks;
        if (used.length >= limit) {
          final again = candidates.where((f) => used.contains(f.name)).toList();
          // Few products, but not the same one two days running: when every
          // one bought was eaten today or yesterday, one more comes in.
          final againFresh = again.where(fresh).toList();
          final anyFresh = candidates.where(fresh).toList();
          if (againFresh.isNotEmpty) {
            candidates = againFresh;
          } else if (varied && anyFresh.isNotEmpty) {
            candidates = anyFresh;
          } else if (again.isNotEmpty) {
            candidates = again;
          }
        }
        final notBefore = candidates
            .where((f) => !previousMeal.contains(f.name))
            .toList();
        if (notBefore.isNotEmpty) candidates = notBefore;
      }
      // Nothing the same day or the day after, when something else fits.
      if (varied) {
        final notRecent = candidates.where(fresh).toList();
        if (notRecent.isNotEmpty) candidates = notRecent;
      }
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
      if (group != null) {
        groupFoods.putIfAbsent(group, () => {}).add(chosen.name);
      }
      return chosen;
    }

    ImportedFood food(GenFood f, [double? grams]) {
      final amount = fixedGrams[f.name] ?? grams;
      return ImportedFood(
        name: f.name,
        amount: amount,
        unit: amount == null ? null : (f.meal.isLiquid ? 'ml' : 'g'),
      );
    }

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
    // Leftover lunches (efficient basket) reuse the previous dinner, so
    // they take no protein of their own from the week's pattern.
    final hasBothMains =
        slots.any((s) => s.baseType == IntakeTypeEntity.lunch) &&
        slots.any((s) => s.baseType == IntakeTypeEntity.dinner);
    bool leftoverDay(int index) =>
        options.efficient && hasBothMains && index.isOdd;
    final cookedPerDay = [
      for (var i = 0; i < options.days.length; i++)
        mainSlots.length -
            (leftoverDay(i)
                ? mainSlots
                      .where((s) => s.baseType == IntakeTypeEntity.lunch)
                      .length
                : 0),
    ];
    final mainCount = cookedPerDay.fold(0, (a, b) => a + b);
    final kinds = _proteinSchedule(
      _pattern[options.effectiveDiet]!,
      mainCount,
      random,
      available: {
        for (final k in ProteinKind.values)
          if (usable.any((f) => _isProteinKind(f, k))) k,
      },
    );
    final weekCounts = [
      for (var w = 0; w < options.days.length; w += 7)
        cookedPerDay
            .sublist(w, math.min(w + 7, cookedPerDay.length))
            .fold(0, (a, b) => a + b),
    ];
    if (options.efficient) _perishablesFirst(kinds, weekCounts);
    // Not the same kind the same day or the next, where another can go.
    _spread(kinds, weekCounts);
    var mainIndex = 0;
    var snackIndex = 0;
    // Leftovers: the dinner just planned, eaten again at the next lunch.
    List<ImportedFood>? lastDinner;
    var dayIndex = -1;

    final days = <ImportedDay>[];
    for (final date in options.days) {
      dayIndex++;
      dayFoods.add(<String>{});
      final meals = <ImportedMeal>[];
      final hasDinner = slots.any((s) => s.baseType == IntakeTypeEntity.dinner);
      for (final slot in slots) {
        final foods = <ImportedFood>[];
        String? dish;
        slotFixed = [...?options.fixed[slot.id]];
        final leftovers =
            leftoverDay(dayIndex) &&
            slot.baseType == IntakeTypeEntity.lunch &&
            hasDinner &&
            lastDinner != null;
        if (leftovers) {
          // Cooked twice the amount last night: the same dish again.
          foods.addAll(lastDinner);
          dish = options.leftoversLabel;
          lastDinner = null;
        } else if (_isMain(slot)) {
          final kind = kinds.isEmpty ? null : kinds[mainIndex % kinds.length];
          mainIndex++;
          final protein = kind == null
              ? pick((f) => f.has('protein') && !f.has('dairy'))
              : pick(
                  (f) => _isProteinKind(f, kind),
                  group: 'protein:${kind.name}',
                );
          if (protein != null) foods.add(food(protein));
          if (kind != ProteinKind.legume) {
            final wholegrain = random.nextDouble() < 0.65;
            // Not eaten today or yesterday first, wholegrain or not.
            final starch =
                pick(
                  (f) =>
                      _isStarch(f) &&
                      f.has('wholegrain') == wholegrain &&
                      fresh(f),
                  group: 'starch',
                ) ??
                pick((f) => _isStarch(f) && fresh(f), group: 'starch') ??
                pick(
                  (f) => _isStarch(f) && f.has('wholegrain') == wholegrain,
                  group: 'starch',
                ) ??
                pick(_isStarch, group: 'starch');
            if (starch != null) foods.add(food(starch));
          }
          final veg = pick(
            (f) => f.has('veg') && !f.has('legume') && !f.has('carb'),
            group: 'veg',
          );
          if (veg != null) {
            foods.add(
              food(veg, veg.conceptId == 'lettuce' ? saladGrams : vegGrams),
            );
          }
          final oil = pick(
            (f) => f.conceptId == 'olive_oil',
            preferOwn: false,
            varied: false,
          );
          if (oil != null) foods.add(food(oil, oilGrams));
        } else if (slot.baseType == IntakeTypeEntity.breakfast) {
          bool isGrain(GenFood f) =>
              f.conceptId == 'bread_slice' ||
              f.conceptId == 'oats' ||
              f.conceptId == 'baguette' ||
              f.conceptId == 'rice_cake';
          final grain =
              pick((f) => isGrain(f) && fresh(f), group: 'grain') ??
              pick(isGrain, group: 'grain');
          if (grain != null) foods.add(food(grain));
          bool isDrink(GenFood f) => options.effectiveDiet == DietStyle.vegan
              ? f.conceptId == 'plant_milk'
              : f.conceptId == 'milk' || f.conceptId == 'yogurt';
          final drink =
              pick((f) => isDrink(f) && fresh(f), group: 'breakfast-drink') ??
              pick(isDrink, group: 'breakfast-drink');
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
                  (f) =>
                      f.conceptId == 'olive_oil' ||
                      f.conceptId == 'avocado' && fresh(f),
                  preferOwn: false,
                  varied: false,
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
            final tomato = pick((f) => f.conceptId == 'tomato' && fresh(f));
            if (tomato != null) foods.add(food(tomato, 60));
          }
          final fruit = pick(
            (f) => f.has('fruit') && !f.has('fat'),
            group: 'fruit',
          );
          if (fruit != null) foods.add(food(fruit, portionGrams(fruit, 120)));
        } else {
          // Snack: a sandwich, or fruit with yogurt and nuts, alternating;
          // the bread, filling, yogurt and nuts fit the meal's points.
          // EatPoint: no sandwich when the bread was eaten today or yesterday.
          final bread = (snackIndex++).isOdd
              ? pick(
                  (f) =>
                      (f.conceptId == 'bread_slice' ||
                          f.conceptId == 'baguette') &&
                      fresh(f),
                )
              : null;
          final sandwich = bread != null;
          if (sandwich) {
            foods.add(food(bread));
            final filling = pick(
              (f) => options.effectiveDiet == DietStyle.vegan
                  ? f.conceptId == 'chickpeas' && f.name.contains('ummus') ||
                        f.conceptId == 'peanut_butter'
                  : f.conceptId == 'turkey_breast' ||
                        f.conceptId == 'ham' ||
                        f.conceptId == 'cheese_slice' ||
                        f.conceptId == 'fresh_cheese' ||
                        f.conceptId == 'tuna_can',
              group: 'filling',
            );
            if (filling != null) foods.add(food(filling));
            final tomato = pick((f) => f.conceptId == 'tomato' && fresh(f));
            if (tomato != null) foods.add(food(tomato, 60));
          } else {
            final fruit = pick(
              (f) => f.has('fruit') && !f.has('fat'),
              group: 'fruit',
            );
            if (fruit != null) foods.add(food(fruit, portionGrams(fruit, 120)));
            // Optional parts of the snack only when not eaten lately.
            final dairy = options.effectiveDiet == DietStyle.vegan
                ? pick(
                    (f) => f.conceptId == 'plant_milk' && fresh(f),
                    group: 'snack-dairy',
                  )
                : pick(
                    (f) => f.conceptId == 'yogurt' && fresh(f),
                    group: 'snack-dairy',
                  );
            if (dairy != null) {
              foods.add(
                food(dairy, dairy.conceptId == 'yogurt' ? yogurtGrams : milkMl),
              );
            }
            // Oats fill the rest of the snack's points.
            final oats = pick((f) => f.conceptId == 'oats' && fresh(f));
            if (oats != null) foods.add(food(oats));
            final nuts = pick(
              (f) => f.has('nuts') && f.conceptId != 'peanut_butter',
              group: 'nuts',
            );
            if (nuts != null) foods.add(food(nuts, nutsGrams));
          }
        }
        // Fixed foods no part of the meal took: added as they are.
        for (final fx in slotFixed) {
          named[fx.food.name] = fx.food;
          fixedGrams[fx.food.name] = fx.grams;
          foods.add(food(fx.food, fx.grams));
        }
        slotFixed = const [];
        for (final f in foods) {
          if (named[f.name]?.conceptId != 'olive_oil') {
            dayFoods.last.add(f.name);
          }
        }
        if (foods.isNotEmpty) {
          meals.add(
            ImportedMeal(label: nameOf(slot), dish: dish, foods: foods),
          );
          if (_isMain(slot)) {
            previousMeal = {for (final f in foods) f.name};
          }
          if (slot.baseType == IntakeTypeEntity.dinner && !leftovers) {
            lastDinner = List.of(foods);
          }
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

  /// Whether [f] is a food of protein [kind].
  static bool isProteinKind(GenFood f, ProteinKind kind) =>
      _isProteinKind(f, kind);

  /// Whether [f] fits [diet], with no exclusions.
  static bool allowedFor(GenFood f, DietStyle diet) =>
      _allowed(f, MenuGeneratorOptions(days: const [], diet: diet));

  /// Reorders each week's [kinds] so the same kind doesn't come back within
  /// three main meals (today and yesterday) where another can, keeping the
  /// order otherwise (perishables first).
  static void _spread(List<ProteinKind> kinds, List<int> weeks) {
    var start = 0;
    for (final count in weeks) {
      final end = math.min(start + count, kinds.length);
      final pool = kinds.sublist(start, end);
      final out = <ProteinKind>[];
      while (pool.isNotEmpty) {
        bool clashes(ProteinKind k, int back) =>
            out.length >= back && out[out.length - back] == k;
        // Three main meals back covers today and yesterday.
        final i = [
          pool.indexWhere(
            (k) => !clashes(k, 1) && !clashes(k, 2) && !clashes(k, 3),
          ),
          pool.indexWhere((k) => !clashes(k, 1) && !clashes(k, 2)),
          pool.indexWhere((k) => !clashes(k, 1)),
          0,
        ].firstWhere((i) => i >= 0);
        out.add(pool.removeAt(i));
      }
      kinds.setRange(start, end, out);
      start = end;
    }
  }

  /// How soon a kind of protein should be eaten after shopping: fresh fish
  /// first, then fresh meat, then eggs and tofu, then pulses.
  static int perishability(ProteinKind kind) => switch (kind) {
    ProteinKind.oilyFish || ProteinKind.whiteFish => 0,
    ProteinKind.poultry || ProteinKind.redMeat || ProteinKind.pork => 1,
    ProteinKind.egg || ProteinKind.tofu => 2,
    ProteinKind.legume => 3,
  };

  /// Orders each week of [kinds] ([weeks] gives how many main meals each
  /// week cooks) so the most perishable come first, keeping the week's mix.
  static void _perishablesFirst(List<ProteinKind> kinds, List<int> weeks) {
    var start = 0;
    for (final count in weeks) {
      final end = math.min(start + count, kinds.length);
      if (end <= start) break;
      final week = kinds.sublist(start, end)
        ..sort((a, b) => perishability(a).compareTo(perishability(b)));
      kinds.setRange(start, end, week);
      start = end;
    }
  }

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
