import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/presentation/planned_meal_editor_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import 'planner_test_support.dart';

void main() {
  setUp(() {
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
  });

  testWidgets('change an amount, take one out, add a suggestion, save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    List<PlannedItem>? saved;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<List<PlannedItem>>(
                  MaterialPageRoute(
                    builder: (_) => PlannedMealEditorScreen(
                      title: 'Lunch',
                      day: DateTime(2026, 11, 28),
                      mealType: IntakeTypeEntity.lunch,
                      items: [
                        plannedItem('Rice', 80),
                        plannedItem('Bread', 40),
                      ],
                      budget: const MacroPoints(carbs: 4, protein: 3, fat: 2),
                      logged: true,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final s = S.of(tester.element(find.byType(PlannedMealEditorScreen)));
    expect(find.text(s.mealEditorLoggedNote), findsOneWidget);

    await tester.enterText(bySemanticsId('meal-editor-amount').first, '120');
    await tester.pump();
    await tester.tap(find.byTooltip(s.plannerRemoveItem).last);
    await tester.pump();
    expect(find.text('Bread'), findsNothing);

    // The meal lacks protein: a suggestion adds a food.
    final suggestion = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.identifier?.startsWith('meal-closer-') ?? false) &&
          w.properties.identifier != 'meal-closer-panel',
    );
    await tester.ensureVisible(suggestion.first);
    await tester.tap(suggestion.first);
    await tester.pumpAndSettle();

    await tester.tap(bySemanticsId('meal-editor-save'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(2));
    expect(saved!.first.name, 'Rice');
    expect(saved!.first.amount, 120);
    expect(saved!.last.points.protein, greaterThan(0));
  });

  testWidgets('fits a phone in Spanish, with and without a known unit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(
        PlannedMealEditorScreen(
          title: 'Comida',
          day: DateTime(2026, 11, 28),
          mealType: IntakeTypeEntity.lunch,
          items: [
            plannedItem('Tortillas de trigo integrales con semillas', 80),
            plannedItem('Salsa de la casa muy especial', 40),
          ],
          budget: const MacroPoints(carbs: 4, protein: 3, fat: 2),
          logged: true,
        ),
        locale: const Locale('es'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('tortillas'), findsWidgets);
  });
}
