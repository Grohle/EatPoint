import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/planner/presentation/dish_picker_screen.dart';

import 'planner_test_support.dart';

void main() {
  group('dishMatchScore', () {
    test('ignores accents, case and word order', () {
      expect(dishMatchScore('Pechuga de pollo', 'POLLO'), greaterThan(0));
      expect(dishMatchScore('Plátano', 'platano'), greaterThan(0));
      expect(dishMatchScore('Pechuga de pollo', 'poll pech'), greaterThan(0));
    });

    test('ranks a name that starts with the query first', () {
      expect(
        dishMatchScore('Arroz integral', 'arroz'),
        greaterThan(dishMatchScore('Pollo con arroz', 'arroz')),
      );
      expect(
        dishMatchScore('Arroz', 'arroz'),
        greaterThan(dishMatchScore('Arroz integral', 'arroz')),
      );
    });

    test('every word must match', () {
      expect(dishMatchScore('Pechuga de pollo', 'pollo atun'), 0);
      expect(dishMatchScore('Lentejas', 'garbanzo'), 0);
    });
  });

  group('DishPickerScreen', () {
    setUp(() async {
      await locator.reset();
      FoodKnowledge.setInstance(
        FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
      );
    });

    tearDown(() => locator.reset());

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        localizedApp(
          DishPickerScreen(day: DateTime(2026, 11, 27), mealType: IntakeTypeEntity.lunch),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('with no dishes it offers to create a recipe or find a food',
        (tester) async {
      await pump(tester);
      expect(bySemanticsId('planner-pick-create-recipe'), findsOneWidget);
      expect(bySemanticsId('planner-pick-find-food'), findsOneWidget);
    });

    testWidgets('typing finds basic foods and offers the databases',
        (tester) async {
      await pump(tester);
      await tester.enterText(
        find.descendant(
          of: bySemanticsId('planner-pick-search'),
          matching: find.byType(TextField),
        ),
        'chick',
      );
      await tester.pumpAndSettle();
      expect(find.text('Basic foods'), findsOneWidget);
      expect(find.textContaining('Chicken'), findsWidgets);
      expect(bySemanticsId('planner-pick-search-databases'), findsOneWidget);
    });

    testWidgets('a search with no match says so', (tester) async {
      await pump(tester);
      await tester.enterText(
        find.descendant(
          of: bySemanticsId('planner-pick-search'),
          matching: find.byType(TextField),
        ),
        'zzzz',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing called'), findsOneWidget);
    });
  });
}
