import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/presentation/planner_screen.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

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

class _NoMealDetail extends Fake implements MealDetailBloc {}

class _NoHome extends Fake implements HomeBloc {}

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
      localizedApp(
        ChangeNotifierProvider<EnergyUnitProvider>(
          create: (_) => EnergyUnitProvider(),
          child: PlannerScreen(initialDay: day, embedded: embedded),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    return S.of(tester.element(find.byType(PlannerScreen)));
  }

  testWidgets('the Menu tab holds each meal\'s diary section', (
    tester,
  ) async {
    locator.registerSingleton<MealDetailBloc>(_NoMealDetail());
    locator.registerSingleton<HomeBloc>(_NoHome());
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
    // The plan and the diary's own section, in the same meal.
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Yogur natural'), findsOneWidget);
    expect(find.text(s.diaryLabel), findsWidgets);
    expect(bySemanticsId('intake-section-menu'), findsWidgets);
    expect(bySemanticsId('my-day-full-diary'), findsOneWidget);
    // The shopping list lives in the bottom bar instead.
    expect(bySemanticsId('planner-shopping-list'), findsNothing);

    // Every way to plan, behind one clear button.
    await tester.tap(bySemanticsId('planner-plan-menu'));
    await tester.pumpAndSettle();
    expect(bySemanticsId('plan-menu-generateMenu'), findsOneWidget);
    expect(bySemanticsId('plan-menu-importMenu'), findsOneWidget);
  });

  testWidgets('the weekly menu on its own keeps its shopping button', (
    tester,
  ) async {
    final s = await open(tester, embedded: false);
    expect(bySemanticsId('planner-shopping-list'), findsOneWidget);
    expect(bySemanticsId('intake-section-menu'), findsNothing);
    expect(bySemanticsId('my-day-full-diary'), findsNothing);
  });
}
