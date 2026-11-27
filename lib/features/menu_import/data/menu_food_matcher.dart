import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/resolve_parsed_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_text_parser.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';

/// Where the nutrition of an imported food came from.
enum MatchOrigin {
  /// A food the user logged, saved or cooked before.
  mine,

  /// The food databases (Open Food Facts and the other enabled sources).
  database,

  /// The AI's estimate, used when nothing else matched.
  estimate,

  /// Nothing found.
  none,
}

class MatchedFood {
  final ImportedFood source;
  final MealEntity? meal;
  final MatchOrigin origin;

  /// Grams the user usually has of a food they ate before.
  final double? usualAmount;

  const MatchedFood(this.source, this.meal, this.origin, {this.usualAmount});

  bool get isMatched => meal != null;
}

/// Finds the nutrition of each imported food: first among the user's own
/// foods (what they logged, their recipes and custom foods), then in the
/// food databases, and last the AI's estimate when it gave one.
class MenuFoodMatcher {
  final _log = Logger('MenuFoodMatcher');
  List<({String key, MealEntity meal, double? usual})>? _mine;

  /// Set false to stay offline (only the user's own foods, EatPoint's food
  /// list and estimates).
  final bool searchDatabases;

  /// Language for the names of foods taken from EatPoint's food list.
  final String languageCode;

  MenuFoodMatcher({this.searchDatabases = true, this.languageCode = 'en'});

  static String key(String name) => MenuTextParser.fold(name)
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<List<({String key, MealEntity meal, double? usual})>>
  _ownFoods() async {
    final cached = _mine;
    if (cached != null) return cached;
    final foods = <String, ({String key, MealEntity meal, double? usual})>{};
    void add(MealEntity meal, double? usual) {
      final k = key(meal.name ?? '');
      if (k.isEmpty) return;
      foods.putIfAbsent(k, () => (key: k, meal: meal, usual: usual));
    }

    try {
      if (locator.isRegistered<GetIntakeUsecase>()) {
        for (final intake
            in await locator<GetIntakeUsecase>().getRecentIntake()) {
          add(intake.meal, intake.amount);
        }
      }
    } catch (e) {
      _log.fine('Recent foods unavailable: $e');
    }
    try {
      if (locator.isRegistered<RecipeDataSource>()) {
        for (final dbo in locator<RecipeDataSource>().getAllRecipes()) {
          final recipe = RecipeEntity.fromDBO(dbo);
          final servings = recipe.servingsCount;
          add(
            recipe.toMealEntity(),
            servings != null && servings > 0
                ? recipe.totalWeightG / servings
                : null,
          );
        }
      }
    } catch (e) {
      _log.fine('Recipes unavailable: $e');
    }
    try {
      if (locator.isRegistered<CustomMealDataSource>()) {
        for (final dbo in locator<CustomMealDataSource>().getAllCustomMeals()) {
          add(MealEntity.fromMealDBO(dbo), null);
        }
      }
    } catch (e) {
      _log.fine('Custom foods unavailable: $e');
    }
    return _mine = foods.values.toList();
  }

  /// How well [query] matches [candidate], 0..1: shared words over the
  /// words of the longer of the two.
  static double score(String query, String candidate) {
    final q = query.split(' ').where((w) => w.length > 1).toSet();
    final c = candidate.split(' ').where((w) => w.length > 1).toSet();
    if (q.isEmpty || c.isEmpty) return 0;
    var shared = 0;
    for (final w in q) {
      if (c.any((x) => x == w || _stem(x) == _stem(w))) shared++;
    }
    final longer = q.length > c.length ? q.length : c.length;
    return shared / longer;
  }

  static String _stem(String w) =>
      w.length > 4 ? w.replaceAll(RegExp(r'(es|s)$'), '') : w;

  Future<MatchedFood> match(ImportedFood food) async {
    final k = key(food.name);
    final own = await _ownFoods();
    ({String key, MealEntity meal, double? usual})? best;
    var bestScore = 0.0;
    for (final f in own) {
      final s = f.key == k ? 1.0 : score(k, f.key);
      if (s > bestScore) {
        bestScore = s;
        best = f;
      }
    }
    if (best != null && bestScore >= 0.6) {
      return MatchedFood(
        food,
        best.meal,
        MatchOrigin.mine,
        usualAmount: best.usual,
      );
    }
    // EatPoint's own food list, with full nutrition and no network.
    final core = FoodKnowledge.instance?.matchFood(food.name);
    if (core != null) {
      return MatchedFood(
        food,
        core.toMealEntity(languageCode),
        MatchOrigin.database,
      );
    }
    if (searchDatabases && locator.isRegistered<ResolveParsedMealsUseCase>()) {
      try {
        final resolved = await locator<ResolveParsedMealsUseCase>().resolve([
          ParsedMealItem(query: food.name),
        ]);
        final item = resolved.isEmpty ? null : resolved.first;
        final meal = item?.selected;
        if (meal != null &&
            !item!.isLowConfidence &&
            meal.nutriments.energyKcal100 != null) {
          return MatchedFood(food, meal, MatchOrigin.database);
        }
      } catch (e) {
        _log.fine('Database search failed for "${food.name}": $e');
      }
    }
    final estimate = food.per100;
    if (estimate != null) {
      return MatchedFood(
        food,
        _estimated(food.name, estimate),
        MatchOrigin.estimate,
      );
    }
    return MatchedFood(food, null, MatchOrigin.none);
  }

  static MealEntity _estimated(String name, ImportedNutrients n) => MealEntity(
    code: 'import-${key(name).replaceAll(' ', '-')}',
    name: name,
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: 'g',
    servingSize: null,
    nutriments: MealNutrimentsEntity(
      energyKcal100: n.kcal,
      carbohydrates100: n.carbs,
      fat100: n.fat,
      proteins100: n.protein,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
    source: MealSourceEntity.custom,
  );
}
