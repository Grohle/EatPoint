import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/label_scan/domain/nutrition_label_parser.dart';

void main() {
  group('Spanish labels', () {
    test('kJ / kcal on one row, <0,5 g values', () {
      final v = NutritionLabelParser.parse([
        'Información nutricional por 100 g',
        'Valor energético 1035 kJ / 247 kcal',
        'Grasas 3,4 g',
        'de las cuales saturadas <0,5 g',
        'Hidratos de carbono 41 g',
        'de los cuales azúcares 4,1 g',
        'Fibra alimentaria 6,8 g',
        'Proteínas 9,6 g',
        'Sal 1,1 g',
      ]);
      expect(v.kcal, 247);
      expect(v.fat, 3.4);
      expect(v.saturatedFat, 0.5);
      expect(v.carbs, 41);
      expect(v.sugars, 4.1);
      expect(v.fiber, 6.8);
      expect(v.protein, 9.6);
      expect(v.salt, 1.1);
      expect(v.perMl, isFalse);
      expect(v.readCount, 8);
      expect(NutritionLabelParser.checkEnergy(v)!.passes, isTrue);
    });

    test('"Grasas de las cuales saturadas" on one row is saturates', () {
      final v = NutritionLabelParser.parse([
        'Grasas 3,4 g',
        'Grasas de las cuales saturadas 0,6 g',
      ]);
      expect(v.fat, 3.4);
      expect(v.saturatedFat, 0.6);
    });

    test('"Hidratos de carbono de los cuales azúcares" is sugars only', () {
      final v = NutritionLabelParser.parse([
        'Hidratos de carbono 41 g',
        'Hidratos de carbono de los cuales azúcares 4,1 g',
      ]);
      expect(v.carbs, 41);
      expect(v.sugars, 4.1);
    });

    test('kJ row and kcal on the next row', () {
      final v = NutritionLabelParser.parse([
        'Valor energético (kJ/kcal) 1035/247',
        'kcal 247',
        'Grasas 3,4 g',
        'Hidratos de carbono 41 g',
        'Proteínas 9,6 g',
      ]);
      expect(v.kcal, 247);
      expect(v.fat, 3.4);
    });

    test('kcal found on the row after a kJ-only energy row', () {
      final v = NutritionLabelParser.parse([
        'Valor energético 1035 kJ',
        '247 kcal',
        'Grasas 3,4 g',
      ]);
      // The kJ row is converted first (1035 / 4.184 = 247).
      expect(v.kcal, 247);
    });

    test('"Energía 247kcal" without a space', () {
      final v = NutritionLabelParser.parse(['Energía 247kcal']);
      expect(v.kcal, 247);
    });

    test('two-column label picks per 100 g when it comes first', () {
      final v = NutritionLabelParser.parse([
        'Por 100 g Por ración (30 g) %IR*',
        'Valor energético 1035 kJ / 247 kcal 311 kJ / 74 kcal 4%',
        'Grasas 3,4 g 1,0 g 1%',
        'Hidratos de carbono 41 g 12 g 5%',
        'Proteínas 9,6 g 2,9 g 6%',
        'Sal 1,1 g 0,33 g 6%',
      ]);
      expect(v.kcal, 247);
      expect(v.fat, 3.4);
      expect(v.carbs, 41);
      expect(v.protein, 9.6);
      expect(v.salt, 1.1);
    });
  });

  group('English labels', () {
    test('UK/EU layout', () {
      final v = NutritionLabelParser.parse([
        'Typical values per 100g',
        'Energy 1035kJ 247kcal',
        'Fat 3.4g',
        'of which saturates 0.6g',
        'Carbohydrate 41g',
        'of which sugars 4.1g',
        'Fibre 6.8g',
        'Protein 9.6g',
        'Salt 1.1g',
      ]);
      expect(v.kcal, 247);
      expect(v.fat, 3.4);
      expect(v.saturatedFat, 0.6);
      expect(v.carbs, 41);
      expect(v.sugars, 4.1);
      expect(v.fiber, 6.8);
      expect(v.protein, 9.6);
      expect(v.salt, 1.1);
    });

    test('US style, per serving only, does not crash', () {
      final v = NutritionLabelParser.parse([
        'Nutrition Facts',
        'Serving size 1 cup (228g)',
        'Calories 250',
        'Total Fat 3g 4%',
        'Saturated Fat 1.5g 8%',
        'Total Carbohydrate 31g 11%',
        'Dietary Fiber 0g 0%',
        'Total Sugars 5g',
        'Protein 5g',
      ]);
      expect(v.fat, 3);
      expect(v.saturatedFat, 1.5);
      expect(v.carbs, 31);
      expect(v.fiber, 0);
      expect(v.sugars, 5);
      expect(v.protein, 5);
    });

    test('US "Calories" row is read as energy', () {
      final v = NutritionLabelParser.parse(['Calories 250 kcal']);
      expect(v.kcal, 250);
    });
  });

  group('columns', () {
    test('per-serving column first: header decides', () {
      final v = NutritionLabelParser.parse([
        'Per serving (30g) Per 100g',
        'Energy 311kJ/74kcal 1035kJ/247kcal',
        'Fat 1.0g 3.4g',
        'Carbohydrate 12g 41g',
        'Protein 2.9g 9.6g',
      ]);
      expect(v.kcal, 247);
      expect(v.fat, 3.4);
      expect(v.carbs, 41);
      expect(v.protein, 9.6);
    });

    test('per-100 g first without header uses the first column', () {
      final v = NutritionLabelParser.parse([
        'Fat 3.4g 1.0g',
        'Protein 9.6g 2.9g',
      ]);
      expect(v.fat, 3.4);
      expect(v.protein, 9.6);
    });

    test('per 100 ml sets perMl', () {
      final v = NutritionLabelParser.parse([
        'Por 100 ml',
        'Valor energético 180 kJ / 43 kcal',
        'Grasas 1,5 g',
        'Hidratos de carbono 5,0 g',
        'Proteínas 3,1 g',
      ]);
      expect(v.perMl, isTrue);
      expect(v.kcal, 43);
      expect(v.carbs, 5);
    });

    test('per 100 g label is not perMl', () {
      expect(
        NutritionLabelParser.parse(['Por 100 g', 'Grasas 1 g']).perMl,
        isFalse,
      );
    });

    test('%IR / %RI columns are ignored', () {
      final v = NutritionLabelParser.parse([
        'Per 100g %RI',
        'Fat 3.4g 5%',
        'Salt 1.1g 18%',
      ]);
      expect(v.fat, 3.4);
      expect(v.salt, 1.1);
      final only = NutritionLabelParser.parse(['Grasas 12 %', 'Sal 3 %']);
      expect(only.fat, isNull);
      expect(only.salt, isNull);
    });
  });

  group('OCR noise', () {
    test('split decimal "3, 4 g"', () {
      expect(NutritionLabelParser.parse(['Grasas 3, 4 g']).fat, 3.4);
    });

    // BUG: _normalise (nutrition_label_parser.dart:244) requires whitespace
    // AFTER the separator (`\s+`), so a space only BEFORE it ("3 ,4 g") is
    // read as 3 instead of 3.4.
    test(
      'split decimal "3 ,4 g"',
      () {
        expect(NutritionLabelParser.parse(['Grasas 3 ,4 g']).fat, 3.4);
      },
    );

    test('O for zero', () {
      expect(NutritionLabelParser.parse(['Proteínas 1O g']).protein, 10);
    });

    // BUG: the O->0 rule (nutrition_label_parser.dart:250) only fires when
    // the O is followed by a digit, "g", "%" or end of row, not by a decimal
    // separator, so "1O,5 g" is read as 1.
    test(
      'O before a decimal separator',
      () {
        expect(NutritionLabelParser.parse(['Proteínas 1O,5 g']).protein, 10.5);
      },
    );

    test('l for one', () {
      expect(NutritionLabelParser.parse(['Azúcares 4,l g']).sugars, 4.1);
    });

    test('split "k J" and "k cal"', () {
      expect(NutritionLabelParser.parse(['Energía 1035 k J']).kcal, 247);
      expect(NutritionLabelParser.parse(['Energía 247 k cal']).kcal, 247);
    });

    test('upper and lower case', () {
      final v = NutritionLabelParser.parse([
        'VALOR ENERGÉTICO 1035 KJ / 247 KCAL',
        'GRASAS 3,4 G',
        'PROTEÍNAS 9,6 G',
      ]);
      expect(v.kcal, 247);
      expect(v.fat, 3.4);
      expect(v.protein, 9.6);
    });

    test('non-breaking spaces', () {
      final v = NutritionLabelParser.parse([
        'Energía 1035 kJ / 247 kcal',
        'Grasas 3,4 g',
      ]);
      expect(v.kcal, 247);
      expect(v.fat, 3.4);
    });

    test('sugars greater than carbs are dropped', () {
      final v = NutritionLabelParser.parse([
        'Hidratos de carbono 4 g',
        'de los cuales azúcares 41 g',
      ]);
      expect(v.carbs, 4);
      expect(v.sugars, isNull);
    });

    test('saturates greater than fat are dropped', () {
      final v = NutritionLabelParser.parse([
        'Grasas 0,6 g',
        'de las cuales saturadas 3,4 g',
      ]);
      expect(v.fat, 0.6);
      expect(v.saturatedFat, isNull);
    });

    test('values over 100 g are rejected', () {
      expect(NutritionLabelParser.parse(['Grasas 341 g']).fat, isNull);
    });

    test('empty and junk input', () {
      expect(NutritionLabelParser.parse([]).readCount, 0);
      expect(
        NutritionLabelParser.parse(['', '   ', 'Lote 12345']).readCount,
        0,
      );
    });
  });

  group('energy', () {
    test('only kJ present is converted', () {
      expect(NutritionLabelParser.parse(['Energía 1035 kJ']).kcal, 247);
    });

    test('kcal wins over kJ when both are present', () {
      expect(NutritionLabelParser.parse(['Energy 1000kJ 240kcal']).kcal, 240);
    });
  });

  group('checkEnergy', () {
    NutritionLabelValues v({
      double? kcal = 247,
      double? fat = 3.4,
      double? carbs = 41,
      double? protein = 9.6,
      double? fiber = 6.8,
    }) => NutritionLabelValues(
      kcal: kcal,
      fat: fat,
      carbs: carbs,
      protein: protein,
      fiber: fiber,
    );

    test('passes within 15 %', () {
      // 3.4*9 + 41*4 + 9.6*4 + 6.8*2 = 30.6 + 164 + 38.4 + 13.6 = 246.6
      final c = NutritionLabelParser.checkEnergy(v())!;
      expect(c.computedKcal, closeTo(246.6, 0.001));
      expect(c.passes, isTrue);
      expect(c.labelKcal, 247);
      expect(NutritionLabelParser.checkEnergy(v(kcal: 270))!.passes, isTrue);
    });

    test('fails outside 15 %', () {
      expect(NutritionLabelParser.checkEnergy(v(kcal: 320))!.passes, isFalse);
      expect(NutritionLabelParser.checkEnergy(v(carbs: 4.1))!.passes, isFalse);
    });

    test('difference is relative to the larger value', () {
      final c = NutritionLabelParser.checkEnergy(v(kcal: 100, fiber: 0))!;
      final computed = c.computedKcal;
      expect(c.difference, closeTo((computed - 100) / computed, 1e-9));
    });

    test('null when a core value is missing', () {
      expect(NutritionLabelParser.checkEnergy(v(kcal: null)), isNull);
      expect(NutritionLabelParser.checkEnergy(v(fat: null)), isNull);
      expect(NutritionLabelParser.checkEnergy(v(carbs: null)), isNull);
      expect(NutritionLabelParser.checkEnergy(v(protein: null)), isNull);
      expect(
        NutritionLabelParser.checkEnergy(NutritionLabelValues.empty),
        isNull,
      );
    });

    test('fibre is optional', () {
      expect(NutritionLabelParser.checkEnergy(v(fiber: null)), isNotNull);
    });

    test('tiny foods pass via the absolute margin', () {
      const water = NutritionLabelValues(
        kcal: 0,
        fat: 0,
        carbs: 0.5,
        protein: 0,
      );
      // computed 2 kcal vs label 0: 100 % relative, 2 kcal absolute.
      final c = NutritionLabelParser.checkEnergy(water)!;
      expect(c.difference, 1.0);
      expect(c.passes, isTrue);
      const off = NutritionLabelValues(kcal: 0, fat: 0, carbs: 2, protein: 0);
      expect(NutritionLabelParser.checkEnergy(off)!.passes, isFalse);
    });

    test('all-zero food passes', () {
      const zero = NutritionLabelValues(kcal: 0, fat: 0, carbs: 0, protein: 0);
      final c = NutritionLabelParser.checkEnergy(zero)!;
      expect(c.difference, 0);
      expect(c.passes, isTrue);
    });

    test('fibre counts 2 kcal/g', () {
      const base = NutritionLabelValues(
        kcal: 100,
        fat: 0,
        carbs: 25,
        protein: 0,
      );
      final withFibre = base.copyWith(fiber: () => 10);
      expect(NutritionLabelParser.checkEnergy(base)!.computedKcal, 100);
      expect(NutritionLabelParser.checkEnergy(withFibre)!.computedKcal, 120);
    });
  });

  group('NutritionLabelValues', () {
    test('readCount, hasCoreValues, toJson, copyWith', () {
      const a = NutritionLabelValues(kcal: 1, fat: 2, carbs: 3, protein: 4);
      expect(a.hasCoreValues, isTrue);
      expect(a.readCount, 4);
      expect(NutritionLabelValues.empty.hasCoreValues, isFalse);
      final b = a.copyWith(fat: () => null, salt: () => 0.5, perMl: true);
      expect(b.fat, isNull);
      expect(b.salt, 0.5);
      expect(b.perMl, isTrue);
      expect(b.kcal, 1);
      expect(a.toJson()['carbs'], 3);
      expect(a.toString(), contains('NutritionLabelValues'));
    });
  });
}
