import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/features/menu_import/data/menu_food_matcher.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

/// The foods the on-phone generator chooses from: the user's own (what
/// they logged, their recipes and custom foods) and EatPoint's food list.
class MenuGeneratorPool {
  MenuGeneratorPool._();

  static final _log = Logger('MenuGeneratorPool');

  static Future<List<GenFood>> build(
    FoodKnowledge knowledge,
    String languageCode,
  ) async {
    final own = <String, MealEntity>{};
    void add(MealEntity meal) {
      final key = MenuFoodMatcher.key(meal.name ?? '');
      if (key.isEmpty) return;
      final n = meal.nutriments;
      if ((n.energyKcal100 ?? 0) <= 0) return;
      own.putIfAbsent(key, () => meal);
    }

    try {
      if (locator.isRegistered<GetIntakeUsecase>()) {
        for (final i in await locator<GetIntakeUsecase>().getRecentIntake()) {
          add(i.meal);
        }
      }
    } catch (e) {
      _log.fine('Recent foods unavailable: $e');
    }
    try {
      if (locator.isRegistered<RecipeDataSource>()) {
        for (final dbo in locator<RecipeDataSource>().getAllRecipes()) {
          add(RecipeEntity.fromDBO(dbo).toMealEntity());
        }
      }
    } catch (e) {
      _log.fine('Recipes unavailable: $e');
    }
    try {
      if (locator.isRegistered<CustomMealDataSource>()) {
        for (final dbo in locator<CustomMealDataSource>().getAllCustomMeals()) {
          add(MealEntity.fromMealDBO(dbo));
        }
      }
    } catch (e) {
      _log.fine('Custom foods unavailable: $e');
    }
    final ownKeys = own.keys.toSet();
    return [
      for (final meal in own.values)
        GenFood.of(meal, knowledge: knowledge, own: true),
      for (final food in knowledge.foods)
        if (!ownKeys.contains(MenuFoodMatcher.key(food.name(languageCode))))
          GenFood.of(food.toMealEntity(languageCode), knowledge: knowledge),
    ];
  }

  /// The user's own dish names, most recent first, for the AI brief.
  static List<String> ownNames(List<GenFood> pool, {int limit = 30}) => [
    for (final f in pool.where((f) => f.own).take(limit)) f.name,
  ];
}

/// Matches the generated menu's foods to the very foods the generator
/// chose (so "Leche sin lactosa" keeps its name), and anything else the
/// usual way.
class GeneratedFoodMatcher extends MenuFoodMatcher {
  final Map<String, GenFood> foods;

  GeneratedFoodMatcher(this.foods, {super.languageCode, super.searchDatabases});

  @override
  Future<MatchedFood> match(ImportedFood food) async {
    final generated = foods[food.name];
    if (generated != null) {
      return MatchedFood(
        food,
        generated.meal,
        generated.own ? MatchOrigin.mine : MatchOrigin.database,
      );
    }
    return super.match(food);
  }
}

/// The instructions for the AI version of the generator: the days, each
/// meal's points, the user's diet and the healthy-eating guides the
/// on-phone version follows.
class MenuGeneratorBrief {
  MenuGeneratorBrief._();

  static String build({
    required List<DateTime> days,
    required List<MealSlot> slots,
    required String Function(MealSlot) nameOf,
    required Map<String, MacroPoints> budgets,
    required DietProfile profile,
    required String languageCode,
    List<String> ownDishes = const [],
    Map<String, List<String>> fixed = const {},
  }) {
    String date(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    String pts(double v) => v.toStringAsFixed(1);
    final lines = <String>[
      'Days: ${days.map(date).join(', ')}.',
      'Write the food names in '
          '${languageCode == 'es' ? 'Spanish' : 'English'}.',
      'Meals of each day, with a budget in points (1 point = 100 kcal from '
          'that macronutrient); size the amounts to fit it:',
      for (final slot in slots)
        if (budgets[slot.id] case final b?)
          '- "${nameOf(slot)}" (${slot.baseType.name}): about '
              '${(b.total * PointsCalc.kcalPerPoint).round()} kcal; '
              'carbs ${pts(b.carbs)}, protein ${pts(b.protein)}, '
              'fat ${pts(b.fat)} points.',
      // EatPoint: foods the user always has in a meal.
      for (final slot in slots)
        if (fixed[slot.id] case final foods? when foods.isNotEmpty)
          'Always include in "${nameOf(slot)}" every day: '
              '${foods.join(', ')} (count them in its budget).',
      'Diet: ${profile.diet.name}.',
      if (profile.religion != ReligiousDiet.none)
        'Religious diet: ${profile.religion.name}'
            '${switch (profile.religion) {
              ReligiousDiet.halal => ' (no pork, alcohol or gelatine)',
              ReligiousDiet.kosher => ' (no pork, shellfish or molluscs; never meat and dairy in the same meal)',
              ReligiousDiet.hindu => ' (no beef)',
              ReligiousDiet.none => '',
            }}.',
      if (profile.allergies.isNotEmpty)
        'ALLERGIES (must never appear, not even as an ingredient of a dish): '
            '${profile.allergies.map((a) => a.name).join(', ')}.'
            '${profile.allergies.contains(Allergen.gluten) ? ' For gluten, certified gluten-free versions are fine; name them "gluten-free".' : ''}',
      if (profile.intolerances.contains(Intolerance.lactose))
        'Lactose intolerance: use lactose-free milk, yogurt and fresh '
            'cheese and say so in the name; aged cheese is fine.',
      if (profile.intolerances.contains(Intolerance.gluten))
        'Gluten intolerance: use gluten-free bread, pasta and cereals and '
            'say so in the name.',
      if (profile.dislikes.isNotEmpty)
        'Never use: ${profile.dislikes.join(', ')}.',
      if (profile.likes.isNotEmpty)
        'The person likes: ${profile.likes.join(', ')}. Include them where '
            'they fit, a few times a week, without repeating on consecutive '
            'days.',
      if (ownDishes.isNotEmpty)
        'Dishes and foods the person often eats (reuse some, by these '
            'names): ${ownDishes.join('; ')}.',
      'Guides: oily fish twice a week and white fish once (when the diet '
          'allows), pulses three times, eggs two or three times, red meat '
          'at most once, little processed meat and no sweets; vegetables at '
          'lunch and dinner, fruit every day, mostly wholegrain cereals, '
          'olive oil as the fat; do not repeat a main protein on '
          'consecutive meals; simple home cooking.',
    ];
    return lines.join('\n');
  }
}
