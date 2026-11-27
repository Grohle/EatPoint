import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/shopping_list_builder.dart';
import 'package:opennutritracker/features/planner/presentation/planner_screen.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/fake_hive_db_provider.dart';
import 'planner_test_support.dart';
import '../points/points_test_support.dart' show registerPointsLocator;

void main() {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  late PlannerDataSource planner;

  setUp(() async {
    await locator.reset();
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
    final box = MemoryStringBox();
    registerPointsLocator(box: box);
    final db = FakeHiveDBProvider(pointsSettingsBox: box);
    planner = PlannerDataSource(db);
    locator.registerSingleton<PlannerDataSource>(planner);
    locator.registerSingleton<TravelModeStore>(TravelModeStore(db));
    await planner.saveDay(
      dayPlan(day, {
        IntakeTypeEntity.lunch: [plannedItem('Arroz', 80)],
        IntakeTypeEntity.dinner: [plannedItem('Salmón', 150)],
      }),
    );
  });

  tearDown(() => locator.reset());

  Future<S> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(PlannerScreen(initialDay: day)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    return S.of(tester.element(find.byType(PlannerScreen)));
  }

  List<String> basket() => [
    for (final item in ShoppingListBuilder.build([
      (owner: 'me', plan: planner.getDay(day)),
    ]))
      item.name,
  ];

  testWidgets('a meal is deleted from the menu and the basket, and undone', (
    tester,
  ) async {
    final s = await open(tester);
    expect(basket(), containsAll(['Arroz', 'Salmón']));

    await tester.tap(bySemanticsId('planner-delete-lunch'));
    await tester.pumpAndSettle();
    expect(planner.getDay(day).itemsFor('lunch'), isEmpty);
    expect(basket(), ['Salmón']);

    await tester.tap(find.text(s.plannerUndo));
    await tester.pumpAndSettle();
    expect(planner.getDay(day).itemsFor('lunch'), hasLength(1));
  });

  testWidgets('the whole day is deleted after asking', (tester) async {
    final s = await open(tester);
    final button = bySemanticsId('planner-delete-day');
    await tester.scrollUntilVisible(
      button,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.plannerDeleteDay));
    await tester.pumpAndSettle();
    expect(planner.getDay(day).isEmpty, isTrue);
    expect(basket(), isEmpty);
  });

  testWidgets('a logged meal\'s header fits in Spanish on a phone', (
    tester,
  ) async {
    await planner.saveDay(planner.getDay(day).withLogged('lunch', true));
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(PlannerScreen(initialDay: day), locale: const Locale('es')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(bySemanticsId('planner-unlog-lunch'), findsOneWidget);
    expect(bySemanticsId('planner-delete-lunch'), findsOneWidget);
  });
}
