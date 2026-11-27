import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/diet_profile/domain/food_facts.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';

void main() {
  setUpAll(() {
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
  });

  group('IngredientLabelParser', () {
    test('reads ingredients, "contains" and traces from a Spanish label', () {
      const text = '''
Galletas integrales
Ingredientes: harina integral de TRIGO (45%), azúcar, aceite de girasol,
LECHE desnatada en polvo, avena, gasificante, sal.
Puede contener trazas de frutos de cáscara, SOJA y SÉSAMO.
Información nutricional por 100 g''';
      final facts = IngredientLabelParser.parse(text);
      expect(facts.ingredients, startsWith('harina integral de TRIGO'));
      expect(
        facts.contains,
        containsAll([DietTrait.gluten, DietTrait.milk, DietTrait.lactose]),
      );
      expect(
        facts.traces,
        containsAll([DietTrait.treeNut, DietTrait.soy, DietTrait.sesame]),
      );
      expect(facts.traces, isNot(contains(DietTrait.gluten)));
    });

    test('reads an English label and its claims', () {
      const text =
          'INGREDIENTS: Oat flakes, almonds (12%), coconut milk, honey. '
          'Contains: oats, almonds. May contain traces of peanuts. '
          'Gluten free. Suitable for vegetarians.';
      final facts = IngredientLabelParser.parse(text);
      expect(facts.contains, containsAll([DietTrait.treeNut, DietTrait.honey]));
      // Coconut milk is not milk; gluten-free oats are fine.
      expect(facts.contains, isNot(contains(DietTrait.milk)));
      expect(facts.contains, isNot(contains(DietTrait.gluten)));
      expect(facts.traces, {DietTrait.peanut});
      expect(
        facts.labels,
        containsAll([FoodLabel.glutenFree, FoodLabel.vegetarian]),
      );
    });

    test('an unrelated text gives no facts', () {
      expect(IngredientLabelParser.parse('Energía 450 kcal').isEmpty, isTrue);
    });
  });

  test('Open Food Facts tags become facts', () {
    final facts = FoodFacts.fromOpenFoodFacts(
      allergens: ['en:milk', 'en:gluten'],
      traces: ['en:nuts', 'en:unknown'],
      labels: ['en:no-lactose', 'en:halal'],
      analysis: ['en:non-vegan', 'en:vegetarian'],
      ingredients: 'Leche sin lactosa, cacao, harina de trigo',
    );
    expect(facts.contains, containsAll([DietTrait.milk, DietTrait.gluten]));
    expect(facts.traces, {DietTrait.treeNut});
    expect(
      facts.labels,
      containsAll([
        FoodLabel.lactoseFree,
        FoodLabel.halal,
        FoodLabel.vegetarian,
      ]),
    );
    expect(facts.labels, isNot(contains(FoodLabel.vegan)));
    expect(FoodFacts.fromJson(facts.toJson()).traces, facts.traces);
  });

  group('the checker with facts', () {
    test('traces warn only for allergies', () {
      const facts = FoodFacts(traces: {DietTrait.peanut});
      const allergic = DietChecker(DietProfile(allergies: {Allergen.peanuts}));
      final c = allergic.check('Barrita de cereales', facts: facts);
      expect(c.single.traces, isTrue);
      expect(c.single.severity, ConflictSeverity.avoid);
      const intolerant = DietChecker(
        DietProfile(intolerances: {Intolerance.lactose}),
      );
      expect(intolerant.check('Barrita de cereales', facts: facts), isEmpty);
    });

    test('the label finds what the name hides', () {
      const facts = FoodFacts(contains: {DietTrait.egg, DietTrait.milk});
      const vegan = DietChecker(DietProfile(diet: DietStyle.vegan));
      expect(vegan.blocks('Pan de molde'), isFalse);
      expect(vegan.blocks('Pan de molde', facts: facts), isTrue);
    });

    test('claims on the pack win over the name', () {
      const vegan = DietChecker(DietProfile(diet: DietStyle.vegan));
      expect(vegan.blocks('Hamburguesa'), isTrue);
      expect(
        vegan.blocks(
          'Hamburguesa',
          facts: const FoodFacts(labels: {FoodLabel.vegan}),
        ),
        isFalse,
      );
      const coeliac = DietChecker(DietProfile(allergies: {Allergen.gluten}));
      expect(coeliac.check('Pan de molde'), isNotEmpty);
      expect(
        coeliac.check(
          'Pan de molde',
          facts: const FoodFacts(labels: {FoodLabel.glutenFree}),
        ),
        isEmpty,
      );
      const halal = DietChecker(DietProfile(religion: ReligiousDiet.halal));
      expect(
        halal.check(
          'Pechuga de pollo',
          facts: const FoodFacts(labels: {FoodLabel.halal}),
        ),
        isEmpty,
      );
    });
  });
}
