import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/presentation/planner_screen.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/fake_hive_db_provider.dart';
import 'planner_test_support.dart';
import '../points/points_test_support.dart' show registerPointsLocator;

class _Diary extends Fake implements IntakeRepository {
  final List<IntakeEntity> intakes;
  _Diary(this.intakes);

  @override
  Future<List<IntakeEntity>> getIntakeByDateAndType(
    IntakeTypeEntity intakeType,
    DateTime dateTime, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [for (final i in intakes) if (i.type == intakeType) i];
}

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
      }),
    );
  });

  tearDown(() => locator.reset());

  Future<S> open(WidgetTester tester, {required bool embedded}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(PlannerScreen(initialDay: day, embedded: embedded)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    return S.of(tester.element(find.byType(PlannerScreen)));
  }

  testWidgets('My day shows what was logged outside the menu', (
    tester,
  ) async {
    locator.registerSingleton<IntakeRepository>(
      _Diary([
        IntakeEntity(
          id: 'i1',
          unit: 'g',
          amount: 125,
          type: IntakeTypeEntity.lunch,
          meal: plannerMeal('Yogur natural'),
          dateTime: day,
        ),
      ]),
    );
    final s = await open(tester, embedded: true);
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Yogur natural'), findsOneWidget);
    expect(find.text(s.myDayLogged), findsOneWidget);
    expect(bySemanticsId('my-day-log-more-lunch'), findsOneWidget);
    expect(bySemanticsId('my-day-full-diary'), findsOneWidget);
    // The shopping list lives in the bottom bar instead.
    expect(bySemanticsId('planner-shopping-list'), findsNothing);
  });

  testWidgets('the weekly menu on its own keeps its shopping button', (
    tester,
  ) async {
    final s = await open(tester, embedded: false);
    expect(bySemanticsId('planner-shopping-list'), findsOneWidget);
    expect(find.text(s.myDayLogged), findsNothing);
    expect(bySemanticsId('my-day-full-diary'), findsNothing);
  });
}
