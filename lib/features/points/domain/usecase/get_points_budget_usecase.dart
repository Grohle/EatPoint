import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';

/// The daily and per-meal points budget for the active profile.
class PointsBudgetResult {
  /// The suggested budget and how it was reached.
  final PointsBudget suggestion;

  /// The budget the user plans with: their own override when they set one,
  /// otherwise the suggestion rounded to quarter points.
  final MacroPoints daily;

  /// The budget of each meal type: the sum of the meals stored under it.
  final Map<IntakeTypeEntity, MacroPoints> perMeal;

  /// The meals of the day, in order.
  final List<MealSlot> slots;

  /// The budget of each meal in [slots], by [MealSlot.id].
  final Map<String, MacroPoints> perSlot;

  /// The day's minimum fibre, in fibre points.
  final double fibreDaily;

  /// Each meal's share of [fibreDaily], by [MealSlot.id].
  final Map<String, double> fibrePerSlot;

  /// True when [daily] is the user's own figure rather than the suggestion.
  final bool isOverridden;

  final PointsSettings settings;

  const PointsBudgetResult({
    required this.suggestion,
    required this.daily,
    required this.perMeal,
    this.slots = const [],
    this.perSlot = const {},
    this.fibreDaily = 0,
    this.fibrePerSlot = const {},
    required this.isOverridden,
    required this.settings,
  });

  /// The budget of the meal [slotId], or of the first meal of [type] when
  /// the meal no longer exists.
  MacroPoints? budgetFor({String? slotId, IntakeTypeEntity? type}) {
    if (slotId != null && perSlot[slotId] != null) return perSlot[slotId];
    final fallback = type == null ? null : slots.defaultFor(type);
    if (fallback != null) return perSlot[fallback.id];
    return type == null ? null : perMeal[type];
  }
}

class GetPointsBudgetUsecase {
  final UserRepository _userRepository;
  final ConfigRepository _configRepository;
  final GetKcalGoalUsecase _getKcalGoalUsecase;
  final PointsSettingsDataSource _settingsDataSource;

  GetPointsBudgetUsecase(
    this._userRepository,
    this._configRepository,
    this._getKcalGoalUsecase,
    this._settingsDataSource,
  );

  Future<PointsBudgetResult> getBudget({UserEntity? userEntity}) async {
    final user = userEntity ?? await _userRepository.getUserData();
    final settings = await _settingsDataSource.getSettings();
    final suggestion = await suggest(user, settings);
    final daily = settings.dailyBudgetOverride ?? suggestion.rounded;
    final slots = settings.effectiveMealSlots;
    final perSlot = slots.budgets(daily);
    final perMeal = <IntakeTypeEntity, MacroPoints>{
      for (final type in IntakeTypeEntity.values) type: MacroPoints.zero,
    };
    for (final slot in slots) {
      perMeal[slot.baseType] = perMeal[slot.baseType]! + perSlot[slot.id]!;
    }
    return PointsBudgetResult(
      suggestion: suggestion,
      daily: daily,
      perMeal: perMeal,
      slots: slots,
      perSlot: perSlot,
      fibreDaily: PointsCalc.snapToStep(
        PointsCalc.fibrePoints(settings.fibreTargetGrams),
      ),
      fibrePerSlot: slots.fibreTargets(
        PointsCalc.snapToStep(
          PointsCalc.fibrePoints(settings.fibreTargetGrams),
        ),
      ),
      isOverridden: settings.dailyBudgetOverride != null,
      settings: settings,
    );
  }

  /// The suggested budget for [user] with [settings], ignoring any override.
  Future<PointsBudget> suggest(UserEntity user, PointsSettings settings) async {
    switch (settings.budgetMethod) {
      case PointsBudgetMethod.leanMass:
        return PointsBudgetCalc.leanMassBudget(
          weightKg: user.weightKG,
          bodyFatPercent: bodyFatPercentFor(user, settings),
          activityMultiplier:
              settings.activityMultiplier ?? activityMultiplierFor(user.pal),
          settings: LeanMassBudgetSettings(
            calorieAdjustment:
                settings.calorieAdjustment ?? calorieAdjustmentFor(user.goal),
            proteinGramsPerKgLeanMass: settings.proteinGramsPerKgLeanMass,
            carbShareOfRemainder: settings.carbShareOfRemainder,
          ),
        );
      case PointsBudgetMethod.appMacros:
        final config = await _configRepository.getConfig();
        final kcalGoal = await _getKcalGoalUsecase.getKcalGoal(
          userEntity: user,
        );
        return PointsBudgetCalc.appMacrosBudget(
          kcalGoal: kcalGoal,
          carbsPercent:
              config.userCarbGoalPct ?? MacroCalc.defaultCarbsPercentageGoal,
          proteinPercent:
              config.userProteinGoalPct ??
              MacroCalc.defaultProteinsPercentageGoal,
          fatPercent:
              config.userFatGoalPct ?? MacroCalc.defaultFatsPercentageGoal,
        );
    }
  }

  /// Body fat from the tape measurements when the user entered them,
  /// otherwise estimated from BMI and age.
  static double bodyFatPercentFor(UserEntity user, PointsSettings settings) {
    final reference = referenceFor(user.gender);
    final neck = settings.neckCm;
    final waist = settings.waistCm;
    if (neck != null && waist != null) {
      final navy = PointsBudgetCalc.bodyFatNavy(
        reference: reference,
        heightCm: user.heightCM,
        neckCm: neck,
        waistCm: waist,
        hipCm: settings.hipCm,
      );
      if (navy != null) return navy;
    }
    return PointsBudgetCalc.bodyFatFromBmi(
      reference: reference,
      weightKg: user.weightKG,
      heightCm: user.heightCM,
      ageYears: user.age,
    );
  }

  static BodyFatReference referenceFor(UserGenderEntity gender) {
    switch (gender) {
      case UserGenderEntity.male:
        return BodyFatReference.male;
      case UserGenderEntity.female:
        return BodyFatReference.female;
      case UserGenderEntity.nonBinary:
        return BodyFatReference.averaged;
    }
  }

  static double activityMultiplierFor(UserPALEntity pal) {
    switch (pal) {
      case UserPALEntity.sedentary:
        return PointsBudgetCalc.sedentaryMultiplier;
      case UserPALEntity.lowActive:
        return PointsBudgetCalc.lightlyActiveMultiplier;
      case UserPALEntity.active:
        return PointsBudgetCalc.moderatelyActiveMultiplier;
      case UserPALEntity.veryActive:
        return PointsBudgetCalc.veryActiveMultiplier;
    }
  }

  static double calorieAdjustmentFor(UserWeightGoalEntity goal) {
    switch (goal) {
      case UserWeightGoalEntity.loseWeight:
        return LeanMassBudgetSettings.loseWeightAdjustment;
      case UserWeightGoalEntity.maintainWeight:
        return LeanMassBudgetSettings.maintainWeightAdjustment;
      case UserWeightGoalEntity.gainWeight:
        return LeanMassBudgetSettings.gainWeightAdjustment;
    }
  }
}
