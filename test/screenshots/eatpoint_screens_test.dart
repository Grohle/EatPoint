import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_import/data/menu_food_matcher.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_text_parser.dart';
import 'package:opennutritracker/features/menu_import/presentation/menu_import_review_screen.dart';
import 'package:opennutritracker/features/menu_import/presentation/menu_import_screen.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/presentation/shopping_list_screen.dart';
import 'package:opennutritracker/features/points/data/meal_slot_assignments.dart';
import 'package:opennutritracker/features/points/presentation/widgets/points_home_switcher.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/presentation/planner_calendar_screen.dart';
import 'package:opennutritracker/features/planner/presentation/planner_screen.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/presentation/meal_slots_screen.dart';
import 'package:opennutritracker/features/points/presentation/onboarding_points_page.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/features/travel/presentation/travel_mode_screen.dart';

import '../features/points/points_test_support.dart';
import '../fixture/user_entity_fixtures.dart';
import '../helpers/fake_hive_db_provider.dart';
import 'screenshot_support.dart';

/// Captures of EatPoint's own screens with a realistic demo day.
void main() {
  late MemoryStringBox box;
  late PlannerDataSource planner;

  final today = DateTime.now();

  setUp(() async {
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
    await locator.reset();
    box = MemoryStringBox();
    final source = registerPointsLocator(box: box);
    await source.saveSettings(
      (await source.getSettings()).copyWith(
        mealSlots: () => demoSlots,
        budgetGuideAcknowledged: true,
      ),
    );
    planner = PlannerDataSource(FakeHiveDBProvider(pointsSettingsBox: box));
    locator.registerSingleton<PlannerDataSource>(planner);
    locator.registerSingleton<TravelModeStore>(
      TravelModeStore(FakeHiveDBProvider(pointsSettingsBox: box)),
    );
    await seedMonth(planner, today);
  });

  tearDown(() => locator.reset());

  for (final locale in const [Locale('en'), Locale('es')]) {
    final tag = locale.languageCode;

    testWidgets('meals screen ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(locale: locale, home: const MealSlotsScreen()),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/meals_screen');

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await capture(tester, '$tag/meals_add_sheet');
    }, skip: !screenshotsEnabled);

    testWidgets('onboarding points step ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: OnboardingPointsPageBody(
                  user: UserEntityFixtures
                      .youngSedentaryMaleWantingToMaintainWeight,
                  initialChoice: const OnboardingPointsChoice(mealsPerDay: 5),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/onboarding_points');
    }, skip: !screenshotsEnabled);

    testWidgets('travel mode ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showTravelModeSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await capture(tester, '$tag/travel_sheet');
    }, skip: !screenshotsEnabled);

    testWidgets('menu import ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      final sample = tag == 'es' ? sampleMenuEs : sampleMenuEn;
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: MenuImportScreen(initialText: sample, initialWeek: today),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/menu_import');

      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: MenuImportReviewScreen(
            menu: MenuTextParser.parse(sample),
            slots: demoSlots,
            initialWeek: today,
            matcher: _DemoMatcher(),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/menu_import_review');
    }, skip: !screenshotsEnabled);

    testWidgets('home points card ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      final assignments = MealSlotAssignments(
        FakeHiveDBProvider(pointsSettingsBox: box),
      );
      locator.registerSingleton<MealSlotAssignments>(assignments);
      final now = DateTime(today.year, today.month, today.day, 12);
      IntakeEntity intake(
        String id,
        MealEntity meal,
        double grams,
        IntakeTypeEntity type,
      ) => IntakeEntity(
        id: id,
        unit: meal.isLiquid ? 'ml' : 'g',
        amount: grams,
        type: type,
        meal: meal,
        dateTime: now,
      );
      final breakfast = [
        intake('b1', oats, 50, IntakeTypeEntity.breakfast),
        intake('b2', milk, 250, IntakeTypeEntity.breakfast),
      ];
      final mid = intake('s1', banana, 120, IntakeTypeEntity.snack);
      final lunch = [
        intake('l1', chicken, 150, IntakeTypeEntity.lunch),
        intake('l2', rice, 220, IntakeTypeEntity.lunch),
        intake('l3', oil, 10, IntakeTypeEntity.lunch),
      ];
      await assignments.assign(mid, 'm-midmorning');
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: Scaffold(
            appBar: AppBar(title: Text(tag == 'es' ? 'Hoy' : 'Today')),
            body: ListView(
              children: [
                PointsHomeSwitcher(
                  intakes: {
                    IntakeTypeEntity.breakfast: breakfast,
                    IntakeTypeEntity.snack: [mid],
                    IntakeTypeEntity.lunch: lunch,
                    IntakeTypeEntity.dinner: const [],
                  },
                  kcalSupplied: 1180,
                  kcalGoal: 2125,
                  caloriesView: const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/home_points');
    }, skip: !screenshotsEnabled);

    testWidgets('shopping list ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      locator.registerSingleton<RecipeDataSource>(
        RecipeDataSource(FakeHiveDBProvider(pointsSettingsBox: box)),
      );
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: ShoppingListScreen(weekOf: today),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/shopping_list');
    }, skip: !screenshotsEnabled);

    testWidgets('weekly menu ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: PlannerScreen(initialDay: today),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/planner_week');

      await tester.tap(find.byIcon(Icons.lightbulb_outline_rounded));
      await tester.pumpAndSettle();
      await capture(tester, '$tag/week_insights');
    }, skip: !screenshotsEnabled);

    testWidgets('menu calendar ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: PlannerCalendarScreen(initialDay: today),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/planner_calendar');
    }, skip: !screenshotsEnabled);
  }
}

final demoSlots = [
  ...MealSlot.builtIn().where((s) => s.baseType == IntakeTypeEntity.breakfast),
  const MealSlot(
    id: 'm-midmorning',
    name: 'Mid-morning',
    baseType: IntakeTypeEntity.snack,
    share: MacroPoints(carbs: 0.1, protein: 0.15, fat: 0.1),
  ),
  ...MealSlot.builtIn().where((s) => s.baseType == IntakeTypeEntity.lunch),
  ...MealSlot.builtIn().where((s) => s.baseType == IntakeTypeEntity.snack),
  ...MealSlot.builtIn().where((s) => s.baseType == IntakeTypeEntity.dinner),
];

MealEntity food(
  String name, {
  required double kcal,
  required double carbs,
  required double protein,
  required double fat,
  double? fibre,
  bool liquid = false,
}) => MealEntity(
  code: name,
  name: name,
  url: null,
  mealQuantity: null,
  mealUnit: liquid ? 'ml' : 'g',
  servingQuantity: null,
  servingUnit: liquid ? 'ml' : 'g',
  servingSize: null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal,
    carbohydrates100: carbs,
    fat100: fat,
    proteins100: protein,
    sugars100: null,
    saturatedFat100: null,
    fiber100: fibre,
  ),
  source: MealSourceEntity.custom,
);

PlannedItem item(MealEntity meal, double amount) => PlannedItem(
  id: '${meal.name}-$amount',
  meal: meal,
  amount: amount,
  unit: meal.isLiquid ? 'ml' : 'g',
);

final oats = food(
  'Oat flakes',
  kcal: 372,
  carbs: 59,
  protein: 13,
  fat: 7,
  fibre: 10,
);
final milk = food(
  'Semi-skimmed milk',
  kcal: 46,
  carbs: 4.8,
  protein: 3.2,
  fat: 1.6,
  liquid: true,
);
final yogurt = food('Greek yogurt', kcal: 97, carbs: 3.6, protein: 9, fat: 5);
final banana = food(
  'Banana',
  kcal: 89,
  carbs: 23,
  protein: 1.1,
  fat: 0.3,
  fibre: 2.6,
);
final chicken = food(
  'Chicken breast',
  kcal: 120,
  carbs: 0,
  protein: 23,
  fat: 2.6,
);
final rice = food(
  'Brown rice (cooked)',
  kcal: 123,
  carbs: 26,
  protein: 2.7,
  fat: 1,
  fibre: 1.8,
);
final salmon = food('Salmon', kcal: 208, carbs: 0, protein: 20, fat: 13);
final potato = food(
  'Baked potato',
  kcal: 93,
  carbs: 21,
  protein: 2.5,
  fat: 0.1,
  fibre: 2.2,
);
final salad = food(
  'Mixed salad',
  kcal: 20,
  carbs: 3,
  protein: 1.3,
  fat: 0.2,
  fibre: 1.8,
);
final oil = food('Olive oil', kcal: 884, carbs: 0, protein: 0, fat: 100);
final toast = food(
  'Whole-wheat toast',
  kcal: 247,
  carbs: 41,
  protein: 13,
  fat: 3.4,
  fibre: 6.8,
);
final almonds = food(
  'Almonds',
  kcal: 579,
  carbs: 22,
  protein: 21,
  fat: 50,
  fibre: 12.5,
);

Future<void> seedMonth(PlannerDataSource planner, DateTime today) async {
  final first = DateTime(today.year, today.month);
  final days = DateUtils.getDaysInMonth(today.year, today.month);
  final menus = [
    {
      'breakfast': [item(oats, 50), item(milk, 250)],
      'm-midmorning': [item(banana, 120)],
      'lunch': [
        item(chicken, 150),
        item(rice, 180),
        item(salad, 100),
        item(oil, 10),
      ],
      'snack': [item(yogurt, 125), item(almonds, 15)],
      'dinner': [item(salmon, 130), item(potato, 200), item(salad, 100)],
    },
    {
      'breakfast': [item(toast, 60), item(yogurt, 125)],
      'm-midmorning': [item(almonds, 20)],
      'lunch': [item(salmon, 120), item(rice, 150), item(salad, 120)],
      'snack': [item(banana, 120)],
      'dinner': [item(chicken, 140), item(potato, 180), item(oil, 8)],
    },
  ];
  for (var d = 1; d <= days; d++) {
    final date = DateTime(first.year, first.month, d);
    // Plan most of the month, leaving a few gaps like a real user.
    if ((d % 9 == 0 && d != today.day) ||
        date.isAfter(today.add(const Duration(days: 10)))) {
      continue;
    }
    final menu = menus[d % menus.length];
    var plan = DayPlan(date: date, meals: menu);
    if (date.isBefore(DateTime(today.year, today.month, today.day))) {
      for (final id in menu.keys) {
        if (d % 5 == 0 && id == 'snack') continue;
        plan = plan.withLogged(id, true);
      }
    }
    await planner.saveDay(plan);
  }
}

const sampleMenuEn = '''Monday
Breakfast: oat flakes 50 g, semi-skimmed milk 250 ml
Mid-morning: banana
Lunch: chicken breast, brown rice, mixed salad, olive oil 10 g
Snack: greek yogurt, almonds 15 g
Dinner: salmon 130 g, baked potato

Tuesday
Breakfast: whole-wheat toast, greek yogurt
Lunch: salmon, brown rice, mixed salad
Dinner: chicken breast, baked potato (1.5 pts)''';

const sampleMenuEs = '''Lunes
Desayuno: copos de avena 50 g, leche semidesnatada 250 ml
Media mañana: plátano
Almuerzo: pechuga de pollo, arroz integral, ensalada, aceite de oliva 10 g
Merienda: yogur griego, almendras 15 g
Cena: salmón 130 g, patata asada

Martes
Desayuno: tostada integral, yogur griego
Almuerzo: salmón, arroz integral, ensalada
Cena: pechuga de pollo, patata asada (1,5 pts)''';

/// Matches the demo foods offline, by English or Spanish name.
class _DemoMatcher extends MenuFoodMatcher {
  _DemoMatcher() : super(searchDatabases: false);

  static final _byName = {
    'oat flakes': oats,
    'copos de avena': oats,
    'semi-skimmed milk': milk,
    'leche semidesnatada': milk,
    'banana': banana,
    'platano': banana,
    'chicken breast': chicken,
    'pechuga de pollo': chicken,
    'brown rice': rice,
    'arroz integral': rice,
    'mixed salad': salad,
    'ensalada': salad,
    'olive oil': oil,
    'aceite de oliva': oil,
    'greek yogurt': yogurt,
    'yogur griego': yogurt,
    'almonds': almonds,
    'almendras': almonds,
    'salmon': salmon,
    'salmon 130': salmon,
    'baked potato': potato,
    'patata asada': potato,
    'whole-wheat toast': toast,
    'whole wheat toast': toast,
    'tostada integral': toast,
  };

  @override
  Future<MatchedFood> match(ImportedFood food) async {
    final meal =
        _byName[MenuFoodMatcher.key(food.name)] ??
        _byName[MenuTextParser.fold(food.name)];
    return MatchedFood(
      food,
      meal,
      meal == null ? MatchOrigin.none : MatchOrigin.mine,
    );
  }
}
