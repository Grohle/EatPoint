import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/planner/domain/pack_sizes.dart';

void main() {
  setUpAll(
    () => FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    ),
  );

  test('a week of chicken in 500 g trays', () {
    final advice = PackSizes.forFood('Pechuga de pollo', 900)!;
    expect(advice.size, 500);
    expect(advice.packs, 2);
    expect(advice.leftover, 100);
  });

  test('a little over a pack does not buy another one', () {
    expect(PackSizes.forFood('Arroz blanco (crudo)', 1020)!.packs, 1);
  });

  test('eggs come in sixes', () {
    final advice = PackSizes.forFood('Huevo', 400)!;
    expect(advice.pieces, 6);
    expect(advice.packs, 2);
  });

  test('foods without a usual pack say nothing', () {
    expect(PackSizes.forFood('Manzana', 600), isNull);
  });
}
