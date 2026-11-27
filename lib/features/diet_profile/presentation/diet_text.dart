import 'package:flutter/material.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/generated/l10n.dart';

extension DietStyleText on DietStyle {
  String label(S s) => switch (this) {
    DietStyle.omnivore => s.dietOmnivore,
    DietStyle.pescatarian => s.dietPescatarian,
    DietStyle.vegetarian => s.dietVegetarian,
    DietStyle.vegan => s.dietVegan,
  };

  String help(S s) => switch (this) {
    DietStyle.omnivore => s.dietOmnivoreHelp,
    DietStyle.pescatarian => s.dietPescatarianHelp,
    DietStyle.vegetarian => s.dietVegetarianHelp,
    DietStyle.vegan => s.dietVeganHelp,
  };
}

extension ReligiousDietText on ReligiousDiet {
  String label(S s) => switch (this) {
    ReligiousDiet.none => s.dietReligionNone,
    ReligiousDiet.halal => s.dietHalal,
    ReligiousDiet.kosher => s.dietKosher,
    ReligiousDiet.hindu => s.dietHindu,
  };

  String? help(S s) => switch (this) {
    ReligiousDiet.none => null,
    ReligiousDiet.halal => s.dietHalalHelp,
    ReligiousDiet.kosher => s.dietKosherHelp,
    ReligiousDiet.hindu => s.dietHinduHelp,
  };
}

extension AllergenText on Allergen {
  String label(S s) => switch (this) {
    Allergen.gluten => s.allergenGluten,
    Allergen.crustaceans => s.allergenCrustaceans,
    Allergen.eggs => s.allergenEggs,
    Allergen.fish => s.allergenFish,
    Allergen.peanuts => s.allergenPeanuts,
    Allergen.soy => s.allergenSoy,
    Allergen.milk => s.allergenMilk,
    Allergen.treeNuts => s.allergenTreeNuts,
    Allergen.celery => s.allergenCelery,
    Allergen.mustard => s.allergenMustard,
    Allergen.sesame => s.allergenSesame,
    Allergen.sulphites => s.allergenSulphites,
    Allergen.lupin => s.allergenLupin,
    Allergen.molluscs => s.allergenMolluscs,
  };
}

extension IntoleranceText on Intolerance {
  String label(S s) => switch (this) {
    Intolerance.lactose => s.dietIntoleranceLactose,
    Intolerance.gluten => s.dietIntoleranceGluten,
  };
}

extension DietTraitText on DietTrait {
  String label(S s) => switch (this) {
    DietTrait.gluten => s.traitGluten,
    DietTrait.milk => s.traitMilk,
    DietTrait.lactose || DietTrait.lowLactose => s.traitLactose,
    DietTrait.egg => s.traitEgg,
    DietTrait.fish => s.traitFish,
    DietTrait.crustacean => s.traitCrustacean,
    DietTrait.mollusc => s.traitMollusc,
    DietTrait.peanut => s.traitPeanut,
    DietTrait.treeNut => s.traitTreeNut,
    DietTrait.soy => s.traitSoy,
    DietTrait.sesame => s.traitSesame,
    DietTrait.celery => s.traitCelery,
    DietTrait.mustard => s.traitMustard,
    DietTrait.sulphites => s.traitSulphites,
    DietTrait.lupin => s.traitLupin,
    DietTrait.meat => s.traitMeat,
    DietTrait.pork => s.traitPork,
    DietTrait.beef => s.traitBeef,
    DietTrait.alcohol => s.traitAlcohol,
    DietTrait.honey => s.traitHoney,
    DietTrait.gelatin => s.traitGelatin,
  };
}

/// The reason for [c] and, when there is one, what to choose instead.
({String reason, String? alternative}) dietConflictText(
  BuildContext context,
  DietProfile profile,
  DietConflict c,
) {
  final s = S.of(context);
  final what = c.trait?.label(s) ?? '';
  final reason = switch (c.reason) {
    DietReason.allergy => s.dietReasonAllergy(
      c.allergen?.label(s).toLowerCase() ?? what,
    ),
    DietReason.intolerance => s.dietReasonIntolerance(what),
    DietReason.diet => s.dietReasonDiet(
      what,
      profile.diet.label(s).toLowerCase(),
    ),
    DietReason.religion => s.dietReasonReligion(
      what,
      profile.religion.label(s).split(' (').first,
    ),
    DietReason.dislike => s.dietReasonDislike(c.word ?? ''),
  };
  final alternative = switch (c.alternative) {
    null => null,
    DietAlternative.lactoseFree => s.dietAltLactoseFree,
    DietAlternative.glutenFree => s.dietAltGlutenFree,
    DietAlternative.certifiedGlutenFree => s.dietAltCertifiedGlutenFree,
    DietAlternative.plantBased => s.dietAltPlantBased,
    DietAlternative.halalMeat => s.dietAltHalalMeat,
    DietAlternative.kosherMeat => s.dietAltKosherMeat,
    DietAlternative.agedCheeseOk => s.dietAltAgedCheese,
  };
  // A note's reason is the alternative itself ("Choose halal meat").
  if (c.severity == ConflictSeverity.note && alternative != null) {
    return (reason: alternative, alternative: null);
  }
  return (reason: reason, alternative: alternative);
}
