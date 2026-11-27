import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';

void main() {
  setUpAll(() {
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
  });

  Set<DietTrait> t(String name) => DietChecker.traitsOf(name);

  group('traitsOf', () {
    test('finds allergens in Spanish and English names', () {
      expect(t('Pan integral'), contains(DietTrait.gluten));
      expect(t('Wholemeal bread'), contains(DietTrait.gluten));
      expect(
        t('Yogur natural'),
        containsAll([DietTrait.milk, DietTrait.lactose]),
      );
      expect(t('Gambas al ajillo'), contains(DietTrait.crustacean));
      expect(t('Mejillones en escabeche'), contains(DietTrait.mollusc));
      expect(t('Hummus'), contains(DietTrait.sesame));
      expect(t('Ensalada con nueces'), contains(DietTrait.treeNut));
    });

    test('free-from versions lose what they are free of', () {
      expect(t('Pan sin gluten'), isNot(contains(DietTrait.gluten)));
      expect(t('Leche sin lactosa'), isNot(contains(DietTrait.lactose)));
      // Still milk: not for a milk allergy.
      expect(t('Leche sin lactosa'), contains(DietTrait.milk));
      expect(t('Bebida de avena'), isNot(contains(DietTrait.milk)));
      expect(t('Oat milk'), isNot(contains(DietTrait.milk)));
      expect(t('Cerveza sin alcohol'), isNot(contains(DietTrait.alcohol)));
    });

    test('knows the tricky names', () {
      // A Spanish tortilla is an omelette; a wheat tortilla is bread.
      expect(t('Tortilla de patatas'), contains(DietTrait.egg));
      expect(t('Tortilla de patatas'), isNot(contains(DietTrait.gluten)));
      expect(t('Tortilla de trigo'), contains(DietTrait.gluten));
      expect(t('Tortilla de trigo'), isNot(contains(DietTrait.egg)));
      // Fish cut like meat.
      expect(t('Lomo de salmón'), isNot(contains(DietTrait.meat)));
      expect(t('Lomo de salmón'), contains(DietTrait.fish));
      expect(t('Lomo de cerdo'), containsAll([DietTrait.meat, DietTrait.pork]));
      expect(t('Hamburguesa de pollo'), contains(DietTrait.meat));
      expect(t('Hamburguesa de pollo'), isNot(contains(DietTrait.beef)));
      expect(t('Hamburguesa vegetal'), isNot(contains(DietTrait.meat)));
      expect(t('Peanut butter'), isNot(contains(DietTrait.milk)));
      expect(t('Queso curado'), contains(DietTrait.lowLactose));
      expect(t('Queso curado'), isNot(contains(DietTrait.lactose)));
      expect(t('Panceta'), isNot(contains(DietTrait.gluten)));
      expect(t('Jamón serrano'), contains(DietTrait.pork));
      expect(t('Hamburguesa'), isNot(contains(DietTrait.pork)));
    });
  });

  group('check', () {
    test('lactose intolerance adapts dairy and is fine with aged cheese', () {
      const c = DietChecker(DietProfile(intolerances: {Intolerance.lactose}));
      final milk = c.check('Leche entera');
      expect(milk.single.severity, ConflictSeverity.adapt);
      expect(milk.single.alternative, DietAlternative.lactoseFree);
      expect(c.check('Leche sin lactosa'), isEmpty);
      expect(c.check('Queso curado').single.severity, ConflictSeverity.note);
      expect(c.adaptedName('Leche', 'es'), 'Leche sin lactosa');
      expect(c.adaptedName('Yogurt', 'en'), 'Lactose-free yogurt');
    });

    test('a milk allergy rules out lactose-free milk too', () {
      const c = DietChecker(DietProfile(allergies: {Allergen.milk}));
      final conflicts = c.check('Leche sin lactosa');
      expect(conflicts.single.severity, ConflictSeverity.avoid);
      expect(conflicts.single.alternative, DietAlternative.plantBased);
      expect(c.check('Bebida de soja'), isEmpty);
    });

    test('coeliac disease takes certified gluten-free versions', () {
      const c = DietChecker(DietProfile(allergies: {Allergen.gluten}));
      final bread = c.check('Pan de molde');
      expect(bread.single.alternative, DietAlternative.certifiedGlutenFree);
      expect(c.blocks('Pan de molde'), isFalse);
      expect(c.adaptedName('Pasta', 'es'), 'Pasta sin gluten');
      expect(c.check('Pan sin gluten'), isEmpty);
    });

    test('diets and religions leave out what they forbid', () {
      const veg = DietChecker(DietProfile(diet: DietStyle.vegetarian));
      expect(veg.blocks('Pechuga de pollo'), isTrue);
      expect(veg.blocks('Merluza'), isTrue);
      expect(veg.blocks('Huevo'), isFalse);
      const vegan = DietChecker(DietProfile(diet: DietStyle.vegan));
      expect(vegan.blocks('Huevo'), isTrue);
      expect(vegan.blocks('Miel'), isTrue);
      expect(vegan.blocks('Bebida de avena'), isFalse);
      const halal = DietChecker(DietProfile(religion: ReligiousDiet.halal));
      expect(halal.blocks('Lomo de cerdo'), isTrue);
      expect(halal.blocks('Vino tinto'), isTrue);
      expect(halal.blocks('Pechuga de pollo'), isFalse);
      expect(
        halal.check('Pechuga de pollo').single.alternative,
        DietAlternative.halalMeat,
      );
      const kosher = DietChecker(DietProfile(religion: ReligiousDiet.kosher));
      expect(kosher.blocks('Gambas'), isTrue);
      const hindu = DietChecker(DietProfile(religion: ReligiousDiet.hindu));
      expect(hindu.blocks('Filete de ternera'), isTrue);
      expect(hindu.blocks('Pechuga de pollo'), isFalse);
    });

    test('dislikes and likes match words, ignoring accents', () {
      const c = DietChecker(
        DietProfile(dislikes: ['coliflor'], likes: ['salmón', 'Aguacate']),
      );
      expect(c.blocks('Coliflor gratinada'), isTrue);
      expect(c.isLiked('Salmon a la plancha'), isTrue);
      expect(c.isLiked('aguacate'), isTrue);
      expect(c.isLiked('Pollo'), isFalse);
    });
  });

  test('the profile reads back what it wrote', () {
    const p = DietProfile(
      diet: DietStyle.pescatarian,
      religion: ReligiousDiet.kosher,
      allergies: {Allergen.peanuts, Allergen.sesame},
      intolerances: {Intolerance.lactose},
      dislikes: ['hígado'],
      likes: ['salmón'],
    );
    final back = DietProfile.fromJson(p.toJson());
    expect(back.diet, p.diet);
    expect(back.religion, p.religion);
    expect(back.allergies, p.allergies);
    expect(back.intolerances, p.intolerances);
    expect(back.dislikes, p.dislikes);
    expect(back.likes, p.likes);
    expect(
      DietProfile.fromJson({
        'diet': 'nonsense',
        'allergies': [1],
      }).isEmpty,
      isTrue,
    );
  });
}
