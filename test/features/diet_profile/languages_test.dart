import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/food_facts.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/label_scan/domain/nutrition_label_parser.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_text_parser.dart';

/// French, German and Italian labels, menus and ingredients.
void main() {
  setUpAll(() {
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
  });

  test('ingredients and allergens in French, German and Italian', () {
    final fr = IngredientLabelParser.parse(
      'Ingrédients : farine de BLÉ, sucre, beurre, ŒUFS frais, sel. '
      'Peut contenir des traces de noisettes.',
    );
    expect(fr.contains, containsAll([DietTrait.gluten, DietTrait.milk]));
    expect(fr.traces, {DietTrait.treeNut});

    final de = IngredientLabelParser.parse(
      'Zutaten: WEIZENMEHL, Zucker, Vollmilchpulver, Haselnüsse, Salz. '
      'Kann Spuren von Erdnüssen enthalten. Vegetarisch.',
    );
    expect(de.contains, containsAll([DietTrait.milk, DietTrait.treeNut]));
    expect(de.traces, {DietTrait.peanut});
    expect(de.labels, {FoodLabel.vegetarian});

    final it = IngredientLabelParser.parse(
      'Ingredienti: farina di grano tenero, latte, uova, sale. '
      'Può contenere tracce di soia e sesamo. Senza glutine.',
    );
    expect(it.contains, containsAll([DietTrait.milk, DietTrait.egg]));
    // The claim on the pack wins.
    expect(it.contains, isNot(contains(DietTrait.gluten)));
    expect(it.traces, containsAll([DietTrait.soy, DietTrait.sesame]));
  });

  test('food names in the three languages', () {
    expect(DietChecker.traitsOf('Jambon de Bayonne', conceptId: ''),
        contains(DietTrait.pork));
    expect(DietChecker.traitsOf('Hähnchenbrust', conceptId: ''),
        contains(DietTrait.meat));
    expect(DietChecker.traitsOf('Hähnchen Brust', conceptId: ''),
        contains(DietTrait.meat));
    expect(DietChecker.traitsOf('Hafermilch', conceptId: ''),
        isNot(contains(DietTrait.milk)));
    expect(DietChecker.traitsOf('Latte di soia', conceptId: ''),
        isNot(contains(DietTrait.milk)));
    expect(DietChecker.traitsOf('Pain sans gluten', conceptId: ''),
        isNot(contains(DietTrait.gluten)));
    expect(DietChecker.traitsOf('Gamberetti', conceptId: ''),
        contains(DietTrait.crustacean));
  });

  test('nutrition labels in French, German and Italian', () {
    final fr = NutritionLabelParser.parse([
      'Valeurs nutritionnelles pour 100 g',
      'Énergie 1550 kJ / 370 kcal',
      'Matières grasses 12 g',
      'dont acides gras saturés 4,5 g',
      'Glucides 55 g',
      'dont sucres 20 g',
      'Fibres alimentaires 3 g',
      'Protéines 8 g',
      'Sel 0,5 g',
    ]);
    expect(fr.kcal, 370);
    expect(fr.fat, 12);
    expect(fr.carbs, 55);
    expect(fr.salt, 0.5);

    final de = NutritionLabelParser.parse([
      'Nährwerte pro 100 g',
      'Brennwert 1550 kJ / 370 kcal',
      'Fett 12 g',
      'davon gesättigte Fettsäuren 4,5 g',
      'Kohlenhydrate 55 g',
      'davon Zucker 20 g',
      'Ballaststoffe 3 g',
      'Eiweiß 8 g',
      'Salz 0,5 g',
    ]);
    expect(de.kcal, 370);
    expect(de.saturatedFat, 4.5);
    expect(de.protein, 8);
    expect(de.salt, 0.5);

    final it = NutritionLabelParser.parse([
      'Valori nutrizionali per 100 g',
      'Energia 1550 kJ / 370 kcal',
      'Grassi 12 g',
      'di cui acidi grassi saturi 4,5 g',
      'Carboidrati 55 g',
      'di cui zuccheri 20 g',
      'Fibre 3 g',
      'Proteine 8 g',
      'Sale 0,5 g',
    ]);
    expect(it.carbs, 55);
    expect(it.sugars, 20);
    expect(it.fiber, 3);
    expect(it.salt, 0.5);
  });

  test('menus in French, German and Italian', () {
    final fr = MenuTextParser.parse(
      'Lundi\nPetit-déjeuner: flocons d\'avoine 50 g\nDîner: saumon 150 g\n'
      'Mardi\nDéjeuner: lentilles 200 g',
    );
    expect(fr.days.map((d) => d.weekday), [1, 2]);
    final de = MenuTextParser.parse(
      'Montag\nFrühstück: Haferflocken 50 g\nAbendessen: Lachs 150 g',
    );
    expect(de.days.single.weekday, 1);
    expect(de.days.single.meals, hasLength(2));
    final it = MenuTextParser.parse(
      'Mercoledì\nColazione: yogurt 125 g\nPranzo: pasta 80 g\nCena: tonno 100 g',
    );
    expect(it.days.single.weekday, 3);
    expect(it.days.single.meals, hasLength(3));
  });
}
