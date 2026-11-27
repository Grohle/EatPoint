import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_meal_points_usage_usecase.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

import '../../fixture/user_entity_fixtures.dart';
import '../../helpers/fake_hive_db_provider.dart';

/// A `Box<String>` held in memory, so settings round-trip through the real
/// data source without touching the disk.
class MemoryStringBox extends Fake implements Box<String> {
  final Map<dynamic, String> data = {};

  @override
  String? get(dynamic key, {String? defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, String value) async => data[key] = value;

  @override
  Future<void> delete(dynamic key) async => data.remove(key);
}

class FakeUserRepository extends Fake implements UserRepository {
  @override
  Future<UserEntity> getUserData() async =>
      UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight;
}

/// Builds a budget from whatever the real data source currently holds, with
/// a fixed suggestion per method so tests can tell the methods apart.
class FakeGetPointsBudgetUsecase extends Fake
    implements GetPointsBudgetUsecase {
  final PointsSettingsDataSource source;

  FakeGetPointsBudgetUsecase(this.source);

  static const leanMassSuggestion = MacroPoints(
    carbs: 10,
    protein: 7.5,
    fat: 5.25,
  );
  static const appMacrosSuggestion = MacroPoints(carbs: 12, protein: 6, fat: 4);

  @override
  Future<PointsBudget> suggest(UserEntity user, PointsSettings settings) async {
    final rounded = settings.budgetMethod == PointsBudgetMethod.leanMass
        ? leanMassSuggestion
        : appMacrosSuggestion;
    return PointsBudget(
      method: settings.budgetMethod,
      kcalGoal: 2000,
      exact: rounded,
      rounded: rounded,
    );
  }

  @override
  Future<PointsBudgetResult> getBudget({UserEntity? userEntity}) async {
    final settings = await source.getSettings();
    final suggestion = await suggest(
      userEntity ??
          UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight,
      settings,
    );
    final daily = settings.dailyBudgetOverride ?? suggestion.rounded;
    final slots = settings.effectiveMealSlots;
    return PointsBudgetResult(
      suggestion: suggestion,
      daily: daily,
      perMeal: PointsBudgetCalc.mealBudgets(
        daily,
        split: settings.effectiveMealSplit,
      ),
      slots: slots,
      perSlot: slots.budgets(daily),
      isOverridden: settings.dailyBudgetOverride != null,
      settings: settings,
    );
  }
}

class FakeGetMealPointsUsageUsecase extends Fake
    implements GetMealPointsUsageUsecase {
  final MacroPoints used;

  FakeGetMealPointsUsageUsecase([this.used = MacroPoints.zero]);

  @override
  Future<MacroPoints> usedIn(IntakeTypeEntity type, DateTime day) async => used;

  @override
  Future<Map<String, MacroPoints>> usedPerSlot(
    DateTime day,
    List<MealSlot> slots,
  ) async => {for (final slot in slots) slot.id: used};
}

/// Registers the locator entries the points widgets read and returns the
/// real data source (backed by [box]).
PointsSettingsDataSource registerPointsLocator({
  MemoryStringBox? box,
  MacroPoints mealUsed = MacroPoints.zero,
}) {
  final source = PointsSettingsDataSource(
    FakeHiveDBProvider(pointsSettingsBox: box ?? MemoryStringBox()),
  );
  locator.registerSingleton<PointsSettingsDataSource>(source);
  locator.registerSingleton<GetPointsBudgetUsecase>(
    FakeGetPointsBudgetUsecase(source),
  );
  locator.registerSingleton<GetMealPointsUsageUsecase>(
    FakeGetMealPointsUsageUsecase(mealUsed),
  );
  locator.registerSingleton<UserRepository>(FakeUserRepository());
  return source;
}

/// 133.33 kcal per 100 g, i.e. 1.33 points per 100 g.
MealEntity pointsTestMeal({bool liquid = false, bool noEnergy = false}) =>
    MealEntity(
      code: 'pts-1',
      name: 'Test food',
      url: null,
      mealQuantity: null,
      mealUnit: liquid ? 'ml' : 'g',
      servingQuantity: null,
      servingUnit: liquid ? 'ml' : 'g',
      servingSize: null,
      nutriments: MealNutrimentsEntity(
        energyKcal100: noEnergy ? null : 133.33,
        carbohydrates100: 20,
        fat100: 3,
        proteins100: 5,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    );

Widget localizedApp(Widget home, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: home,
    );

/// Finds the widget wrapped by `Semantics(identifier: id)`.
Finder bySemanticsId(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

Finder fieldWithId(String id) =>
    find.descendant(of: bySemanticsId(id), matching: find.byType(TextField));
