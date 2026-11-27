import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/label_scan/domain/nutrition_label_parser.dart';

void main() {
  test('Spanish label with per-100 g and per-serving columns', () {
    final v = NutritionLabelParser.parse([
      'Información nutricional Por 100 g Por ración (30 g) %IR*',
      'Valor energético 1035 kJ / 247 kcal 311 kJ / 74 kcal 4%',
      'Grasas 3,4 g 1,0 g 1%',
      'de las cuales saturadas 0,6 g 0,2 g 1%',
      'Hidratos de carbono 41 g 12 g 5%',
      'de los cuales azúcares 4,l g 1,2 g 1%',
      'Fibra alimentaria 6,8 g 2,0 g',
      'Proteínas 9,6 g 2,9 g 6%',
      'Sal 1,1 g 0,33 g 6%',
    ]);
    expect(v.kcal, 247);
    expect(v.fat, 3.4);
    expect(v.saturatedFat, 0.6);
    expect(v.carbs, 41);
    expect(v.sugars, 4.1);
    expect(v.fiber, 6.8);
    expect(v.protein, 9.6);
    expect(v.salt, 1.1);
    expect(NutritionLabelParser.checkEnergy(v)!.passes, isTrue);
  });

  test('English label, per-serving column first', () {
    final v = NutritionLabelParser.parse([
      'Nutrition information Per serving (30g) Per 100g',
      'Energy 311kJ/74kcal 1035kJ/247kcal',
      'Fat 1.0g 3.4g',
      'of which saturates 0.2g 0.6g',
      'Carbohydrate 12g 41g',
      'of which sugars 1.2g 4.1g',
      'Fibre 2.0g 6.8g',
      'Protein 2.9g 9.6g',
      'Salt 0.33g 1.1g',
    ]);
    expect(v.kcal, 247);
    expect(v.fat, 3.4);
    expect(v.carbs, 41);
    expect(v.protein, 9.6);
  });

  test('misread carbs fail the energy check', () {
    final v = NutritionLabelParser.parse([
      'Energía 247 kcal',
      'Grasas 3,4 g',
      'Hidratos de carbono 4,1 g',
      'Fibra 6,8 g',
      'Proteínas 9,6 g',
    ]);
    final check = NutritionLabelParser.checkEnergy(v)!;
    expect(check.passes, isFalse);
    expect(check.computedKcal.round(), 99);
  });
}
