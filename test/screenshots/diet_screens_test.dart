import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diet_profile/data/diet_profile_store.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_profile_screen.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_warning.dart';
import 'package:opennutritracker/features/diet_profile/presentation/onboarding_diet_page.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/label_scan/data/label_text_reader.dart';
import 'package:opennutritracker/features/label_scan/presentation/label_scan_screen.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/features/menu_generator/presentation/menu_generator_screen.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/presentation/dish_picker_screen.dart';

import '../features/points/points_test_support.dart';
import '../helpers/fake_hive_db_provider.dart';
import 'eatpoint_screens_test.dart' show demoSlots;
import 'screenshot_support.dart';

/// Captures of "Your diet", the menu generator and the diet warnings.
void main() {
  final today = DateTime.now();
  setUp(() async {
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
    await locator.reset();
    final box = MemoryStringBox();
    final source = registerPointsLocator(box: box);
    await source.saveSettings(
      (await source.getSettings()).copyWith(
        mealSlots: () => demoSlots,
        budgetGuideAcknowledged: true,
      ),
    );
    final db = FakeHiveDBProvider(pointsSettingsBox: box);
    locator.registerSingleton<PlannerDataSource>(PlannerDataSource(db));
    final store = DietProfileStore(db);
    await store.save(
      const DietProfile(
        diet: DietStyle.omnivore,
        religion: ReligiousDiet.halal,
        allergies: {Allergen.peanuts, Allergen.crustaceans},
        intolerances: {Intolerance.lactose, Intolerance.gluten},
        likes: ['salmón', 'aguacate', 'lentejas'],
        dislikes: ['coliflor'],
      ),
    );
    locator.registerSingleton<DietProfileStore>(store);
  });

  tearDown(() => locator.reset());

  for (final locale in const [Locale('en'), Locale('es')]) {
    final tag = locale.languageCode;

    testWidgets('diet profile ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(locale: locale, home: const DietProfileScreen()),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/diet_profile_1');
      final list = find.byType(Scrollable).first;
      tester.state<ScrollableState>(list).position.jumpTo(700);
      await tester.pumpAndSettle();
      await capture(tester, '$tag/diet_profile_2');
    }, skip: !screenshotsEnabled);

    testWidgets('menu generator ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: MenuGeneratorScreen(initialDay: today),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/generator');
      final generate = find.bySemanticsIdentifier('generator-generate');
      await tester.scrollUntilVisible(
        generate,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(generate);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/generator_review');
    }, skip: !screenshotsEnabled);

    testWidgets('diet warnings ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      final es = tag == 'es';
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: Scaffold(
            appBar: AppBar(title: Text(es ? 'Avisos' : 'Warnings')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final name in es
                    ? [
                        'Leche entera',
                        'Pan de molde',
                        'Gambas al ajillo',
                        'Pechuga de pollo',
                        'Queso curado',
                      ]
                    : [
                        'Whole milk',
                        'Sliced bread',
                        'Garlic prawns',
                        'Chicken breast',
                        'Aged cheese',
                      ])
                  DietWarning(
                    name,
                    showName: true,
                    margin: const EdgeInsets.only(bottom: 12),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/diet_warnings');

      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: DishPickerScreen(
            day: today,
            mealType: IntakeTypeEntity.breakfast,
            remaining: const MacroPoints(carbs: 3, protein: 1, fat: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.bySemanticsIdentifier('planner-pick-search'),
          matching: find.byType(TextField),
        ),
        es ? 'pan' : 'bread',
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/dish_picker_diet');
    }, skip: !screenshotsEnabled);

    testWidgets('onboarding diet step ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: OnboardingDietPageBody(
                  initialProfile: const DietProfile(
                    allergies: {Allergen.treeNuts},
                    intolerances: {Intolerance.lactose},
                  ),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, '$tag/onboarding_diet');
    }, skip: !screenshotsEnabled);

    testWidgets('label scan ingredients ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: LabelScanScreen(
            imagePath: 'test/screenshots/fixtures/label_photo.png',
            reader: _LabelReader(),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.bySemanticsIdentifier('label-scan-ingredients-field'),
        matching: find.byType(TextField),
      );
      await tester.scrollUntilVisible(
        field,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        field,
        tag == 'es'
            ? 'Copos de avena, almendras (12 %), miel, leche en polvo, '
                  'aceite de girasol. Puede contener trazas de cacahuete y '
                  'sésamo.'
            : 'Oat flakes, almonds (12%), honey, milk powder, sunflower '
                  'oil. May contain traces of peanuts and sesame.',
      );
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.bySemanticsIdentifier('diet-warning'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await settleAssets(tester);
      await capture(tester, '$tag/label_scan_ingredients');
    }, skip: !screenshotsEnabled);
  }
}

class _LabelReader implements LabelTextReader {
  @override
  Future<List<String>> readRows(String imagePath) async => const [
    'Información nutricional por 100 g',
    'Valor energético 1850 kJ / 441 kcal',
    'Grasas 15 g',
    'de las cuales saturadas 2,1 g',
    'Hidratos de carbono 64 g',
    'de los cuales azúcares 19 g',
    'Fibra alimentaria 7,5 g',
    'Proteínas 8,9 g',
    'Sal 0,6 g',
  ];

  @override
  Future<void> close() async {}
}
