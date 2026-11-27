import 'dart:io';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/meal_closer/domain/meal_closer.dart';
import 'package:opennutritracker/features/meal_closer/presentation/meal_closer_panel.dart';

import '../points/points_test_support.dart';

void main() {
  setUp(() {
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
  });

  testWidgets('says what is missing and offers foods to pick', (tester) async {
    CloserSuggestion? picked;
    await tester.pumpWidget(
      localizedApp(
        MealCloserPanel(
          gap: const MealGap(
            macros: MacroPoints(carbs: 0, protein: 1.5, fat: 0.5),
          ),
          onPick: (c) => picked = c,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Still missing'), findsOneWidget);
    expect(find.textContaining('protein'), findsWidgets);
    final first = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.identifier?.startsWith('meal-closer-') ?? false) &&
          w.properties.identifier != 'meal-closer-panel',
    );
    expect(first, findsWidgets);
    await tester.tap(first.first);
    expect(picked, isNotNull);
    expect(picked!.points.protein, greaterThan(0));
  });

  testWidgets('a complete meal says so', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        const MealCloserPanel(gap: MealGap(macros: MacroPoints.zero)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('complete'), findsOneWidget);
  });
}
