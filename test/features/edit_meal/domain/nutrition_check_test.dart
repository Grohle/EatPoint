import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/edit_meal/domain/nutrition_check.dart';

void main() {
  test('values that add up pass', () {
    expect(
      NutritionCheck.of(kcal: 355, carbs: 60, protein: 13, fat: 7),
      isNull,
    );
  });

  test('fibre counts at 2 kcal per gram, as on European labels', () {
    // 4*10 + 4*20 + 9*2 = 138; with 15 g of fibre, 168.
    expect(
      NutritionCheck.of(kcal: 168, carbs: 10, protein: 20, fat: 2),
      isNotNull,
    );
    expect(
      NutritionCheck.of(kcal: 168, carbs: 10, protein: 20, fat: 2, fibre: 15),
      isNull,
    );
  });

  test('rounding on small values is not a mismatch', () {
    expect(NutritionCheck.of(kcal: 13, carbs: 0.1, protein: 0.4, fat: 1.1), isNull);
  });

  test('a mismatch says what each macro brings', () {
    final check = NutritionCheck.of(kcal: 500, carbs: 60, protein: 13, fat: 7)!;
    expect(check.expectedKcal, 355);
    expect(check.carbsKcal, 240);
    expect(check.proteinKcal, 52);
    expect(check.fatKcal, 63);
    expect(check.looksLikeKj, isFalse);
  });

  test('energy entered in kJ is recognised', () {
    final check = NutritionCheck.of(kcal: 1485, carbs: 60, protein: 13, fat: 7)!;
    expect(check.looksLikeKj, isTrue);
  });

  test('missing values are not checked', () {
    expect(NutritionCheck.of(kcal: 500, carbs: null, protein: 13, fat: 7), isNull);
  });
}
