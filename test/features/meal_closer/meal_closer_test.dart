import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/meal_closer/domain/meal_closer.dart';

void main() {
  final knowledge = FoodKnowledge.parse(
    File(FoodKnowledge.assetPath).readAsStringSync(),
  );

  void show(List<CloserSuggestion> list) {
    for (final c in list) {
      // ignore: avoid_print
      print(
        '${c.food.nameEs}: ${c.grams} g  C${c.points.carbs.toStringAsFixed(2)} '
        'P${c.points.protein.toStringAsFixed(2)} '
        'G${c.points.fat.toStringAsFixed(2)} '
        'F${c.fibre.toStringAsFixed(2)} covers ${c.covers.toStringAsFixed(2)}',
      );
    }
  }

  test('the gap is what is left, never below zero', () {
    final gap = MealGap.of(
      budget: const MacroPoints(carbs: 3, protein: 2, fat: 1),
      used: const MacroPoints(carbs: 3.5, protein: 0.5, fat: 0.5),
      fibreTarget: 1.5,
      fibreUsed: 0.5,
    );
    expect(gap.macros.carbs, 0);
    expect(gap.macros.protein, 1.5);
    expect(gap.macros.fat, 0.5);
    expect(gap.fibre, 1);
    expect(gap.hasCarbs, isFalse);
    expect(gap.isClosed, isFalse);
  });

  test('a closed meal gets no suggestions', () {
    final gap = MealGap.of(
      budget: const MacroPoints(carbs: 2, protein: 2, fat: 1),
      used: const MacroPoints(carbs: 2, protein: 1.9, fat: 1),
    );
    expect(gap.isClosed, isTrue);
    expect(MealCloser.suggest(gap, knowledge), isEmpty);
  });

  test('missing protein suggests lean protein that stays within budget', () {
    const gap = MealGap(macros: MacroPoints(carbs: 0, protein: 1.5, fat: 0.25));
    final list = MealCloser.suggest(gap, knowledge);
    show(list);
    expect(list, isNotEmpty);
    expect(list.first.points.protein, greaterThan(0.75));
    for (final c in list) {
      expect(c.points.carbs, lessThanOrEqualTo(MealCloser.tolerance + 1e-9));
      expect(
        c.points.fat,
        lessThanOrEqualTo(0.25 + MealCloser.tolerance + 1e-9),
      );
      expect(c.food.tags, isNot(contains('sweet')));
    }
  });

  test('missing carbs and fibre suggests fibre-rich carbs', () {
    const gap = MealGap(
      macros: MacroPoints(carbs: 2, protein: 0, fat: 0),
      fibre: 1,
    );
    final list = MealCloser.suggest(gap, knowledge);
    show(list);
    expect(list, isNotEmpty);
    expect(list.first.points.carbs, greaterThan(1));
    expect(list.any((c) => c.fibre >= 0.5), isTrue);
  });

  test('suggestions are varied and use household halves', () {
    const gap = MealGap(macros: MacroPoints(carbs: 2, protein: 2, fat: 1));
    final list = MealCloser.suggest(gap, knowledge);
    show(list);
    expect(list.map((c) => c.food.conceptId).toSet(), hasLength(list.length));
    // Sweets are never offered, whether the food or its kind is tagged.
    final fatOnly = MealCloser.suggest(
      const MealGap(macros: MacroPoints(carbs: 1, protein: 0, fat: 1)),
      knowledge,
      limit: 20,
    );
    expect(fatOnly.map((c) => c.food.id), isNot(contains('dark_chocolate')));
    expect(list.length, lessThanOrEqualTo(4));
  });
}
