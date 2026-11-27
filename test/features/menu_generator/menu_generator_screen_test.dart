import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diet_profile/data/diet_profile_store.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_generator/data/menu_generator_sources.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/features/menu_generator/presentation/menu_generator_screen.dart';
import 'package:opennutritracker/features/menu_import/presentation/menu_import_review_screen.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../points/points_test_support.dart';

void main() {
  setUp(() async {
    await locator.reset();
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
    final box = MemoryStringBox();
    registerPointsLocator(box: box);
    final db = FakeHiveDBProvider(pointsSettingsBox: box);
    locator.registerSingleton<PlannerDataSource>(PlannerDataSource(db));
    final store = DietProfileStore(db);
    await store.save(
      const DietProfile(
        intolerances: {Intolerance.lactose},
        allergies: {Allergen.peanuts},
        likes: ['salmón'],
      ),
    );
    locator.registerSingleton<DietProfileStore>(store);
  });

  tearDown(() => locator.reset());

  testWidgets('shows the diet and generates a menu to review', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(MenuGeneratorScreen(initialDay: DateTime(2026, 11, 30))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Allergies: peanuts'), findsOneWidget);
    expect(find.textContaining('Likes: salmón'), findsOneWidget);
    // Without an AI provider only the phone engine can be chosen.
    expect(find.textContaining('Set up an AI provider'), findsOneWidget);

    await tester.tap(find.text('3 days'));
    await tester.pumpAndSettle();
    final generate = bySemanticsId('generator-generate');
    await tester.scrollUntilVisible(
      generate,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(generate);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MenuImportReviewScreen), findsOneWidget);
  });

  test('the AI brief carries the meals, points and diet', () {
    final slots = MealSlot.builtIn();
    final brief = MenuGeneratorBrief.build(
      days: [DateTime(2026, 11, 30), DateTime(2026, 12, 1)],
      slots: slots,
      nameOf: (s) => s.baseType.name,
      budgets: {
        for (final s in slots)
          s.id: const MacroPoints(carbs: 2, protein: 1.5, fat: 1),
      },
      profile: const DietProfile(
        diet: DietStyle.vegetarian,
        religion: ReligiousDiet.hindu,
        allergies: {Allergen.sesame},
        intolerances: {Intolerance.lactose},
        dislikes: ['coliflor'],
        likes: ['lentejas'],
      ),
      languageCode: 'es',
    );
    expect(brief, contains('2026-11-30, 2026-12-01'));
    expect(brief, contains('Spanish'));
    expect(brief, contains('"lunch"'));
    expect(brief, contains('protein 1.5'));
    expect(brief, contains('vegetarian'));
    expect(brief, contains('no beef'));
    expect(brief, contains('ALLERGIES'));
    expect(brief, contains('sesame'));
    expect(brief, contains('lactose-free'));
    expect(brief, contains('Never use: coliflor'));
    expect(brief, contains('likes: lentejas'));
  });
}
