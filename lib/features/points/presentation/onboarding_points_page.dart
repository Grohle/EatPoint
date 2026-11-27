import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// What the user chose on the onboarding points page.
class OnboardingPointsChoice {
  final PointsBudgetMethod method;
  final int mealsPerDay;
  final bool rebalanceOverspend;

  const OnboardingPointsChoice({
    this.method = PointsBudgetMethod.leanMass,
    this.mealsPerDay = 4,
    this.rebalanceOverspend = true,
  });

  OnboardingPointsChoice copyWith({
    PointsBudgetMethod? method,
    int? mealsPerDay,
    bool? rebalanceOverspend,
  }) => OnboardingPointsChoice(
    method: method ?? this.method,
    mealsPerDay: mealsPerDay ?? this.mealsPerDay,
    rebalanceOverspend: rebalanceOverspend ?? this.rebalanceOverspend,
  );

  /// The meals of the day for [mealsPerDay], named in the user's language.
  List<MealSlot> slots(BuildContext context) =>
      OnboardingMealPresets.slots(context, mealsPerDay);

  /// Saves the choice as the active profile's points settings. Called once
  /// onboarding has saved the profile.
  Future<void> save(BuildContext context) async {
    if (!locator.isRegistered<PointsSettingsDataSource>()) return;
    final slots = mealsPerDay == 4 ? null : this.slots(context);
    final source = locator<PointsSettingsDataSource>();
    final current = await source.getSettings();
    await source.saveSettings(
      current.copyWith(
        budgetMethod: method,
        mealSlots: () => slots,
        rebalanceOverspend: rebalanceOverspend,
      ),
    );
  }
}

/// Typical days of 3 to 6 meals, with how each meal shares the day's
/// points.
class OnboardingMealPresets {
  OnboardingMealPresets._();

  static const counts = [3, 4, 5, 6];

  static List<MealSlot> slots(BuildContext context, int count) {
    final s = S.of(context);
    MealSlot builtIn(IntakeTypeEntity type, double c, double p, double f) =>
        MealSlot(
          id: type.name,
          baseType: type,
          share: MacroPoints(carbs: c, protein: p, fat: f),
        );
    MealSlot custom(String id, String name, double c, double p, double f) =>
        MealSlot(
          id: id,
          name: name,
          baseType: IntakeTypeEntity.snack,
          share: MacroPoints(carbs: c, protein: p, fat: f),
        );
    switch (count) {
      case 3:
        return [
          builtIn(IntakeTypeEntity.breakfast, 0.3, 0.25, 0.3),
          builtIn(IntakeTypeEntity.lunch, 0.4, 0.4, 0.35),
          builtIn(IntakeTypeEntity.dinner, 0.3, 0.35, 0.35),
        ];
      case 5:
        return [
          builtIn(IntakeTypeEntity.breakfast, 0.25, 0.05, 0.35),
          custom(
            'mid-morning',
            s.mealSlotsSuggestionMidMorning,
            0.1,
            0.15,
            0.1,
          ),
          builtIn(IntakeTypeEntity.lunch, 0.3, 0.35, 0.2),
          MealSlot(
            id: IntakeTypeEntity.snack.name,
            name: s.mealSlotsSuggestionAfternoon,
            baseType: IntakeTypeEntity.snack,
            share: const MacroPoints(carbs: 0.15, protein: 0.15, fat: 0.15),
          ),
          builtIn(IntakeTypeEntity.dinner, 0.2, 0.3, 0.2),
        ];
      case 6:
        return [
          builtIn(IntakeTypeEntity.breakfast, 0.2, 0.05, 0.3),
          custom(
            'mid-morning',
            s.mealSlotsSuggestionMidMorning,
            0.1,
            0.15,
            0.1,
          ),
          builtIn(IntakeTypeEntity.lunch, 0.3, 0.3, 0.2),
          MealSlot(
            id: IntakeTypeEntity.snack.name,
            name: s.mealSlotsSuggestionAfternoon,
            baseType: IntakeTypeEntity.snack,
            share: const MacroPoints(carbs: 0.12, protein: 0.12, fat: 0.12),
          ),
          builtIn(IntakeTypeEntity.dinner, 0.2, 0.28, 0.2),
          custom('late-snack', s.mealSlotsSuggestionLate, 0.08, 0.1, 0.08),
        ];
      default:
        return MealSlot.builtIn();
    }
  }
}

/// Onboarding page: how EatPoint's points work, the suggested daily budget
/// (always a guide), the budget method and the meals of the user's day.
class OnboardingPointsPageBody extends StatefulWidget {
  /// The profile entered so far; null until the earlier pages are done.
  final UserEntity? user;
  final OnboardingPointsChoice initialChoice;
  final ValueChanged<OnboardingPointsChoice> onChanged;

  const OnboardingPointsPageBody({
    super.key,
    required this.user,
    required this.onChanged,
    this.initialChoice = const OnboardingPointsChoice(),
  });

  @override
  State<OnboardingPointsPageBody> createState() =>
      _OnboardingPointsPageBodyState();
}

class _OnboardingPointsPageBodyState extends State<OnboardingPointsPageBody> {
  late OnboardingPointsChoice _choice = widget.initialChoice;

  void _set(OnboardingPointsChoice next) {
    setState(() => _choice = next);
    widget.onChanged(next);
  }

  PointsBudget? get _suggestion {
    final user = widget.user;
    if (user == null) return null;
    switch (_choice.method) {
      case PointsBudgetMethod.leanMass:
        return PointsBudgetCalc.leanMassBudget(
          weightKg: user.weightKG,
          bodyFatPercent: GetPointsBudgetUsecase.bodyFatPercentFor(
            user,
            PointsSettings.defaults,
          ),
          activityMultiplier: GetPointsBudgetUsecase.activityMultiplierFor(
            user.pal,
          ),
          settings: LeanMassBudgetSettings(
            calorieAdjustment: GetPointsBudgetUsecase.calorieAdjustmentFor(
              user.goal,
            ),
          ),
        );
      case PointsBudgetMethod.appMacros:
        return PointsBudgetCalc.appMacrosBudget(
          kcalGoal: CalorieGoalCalc.getTotalKcalGoal(user, 0),
          carbsPercent: MacroCalc.defaultCarbsPercentageGoal,
          proteinPercent: MacroCalc.defaultProteinsPercentageGoal,
          fatPercent: MacroCalc.defaultFatsPercentageGoal,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final format = PointsFormat.of(context);
    final suggestion = _suggestion;
    final daily = suggestion?.rounded;
    final slots = _choice.slots(context);
    final perSlot = daily == null ? null : slots.budgets(daily);

    Widget macro(String label, Color color, double value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: Dimens.borderRadiusM,
        ),
        child: Column(
          children: [
            Text(
              format.points(value),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.onboardingPointsTitle, style: theme.textTheme.headlineSmall),
        const SizedBox(height: Dimens.spacing8),
        Text(s.onboardingPointsIntro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Dimens.spacing16),
        if (daily != null) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(Dimens.spacing16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    s.onboardingPointsSuggested(format.points(daily.total)),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: Dimens.spacing12),
                  Row(
                    children: [
                      macro(s.pointsCarbsLabel, palette.carbs, daily.carbs),
                      const SizedBox(width: Dimens.spacing8),
                      macro(
                        s.pointsProteinLabel,
                        palette.protein,
                        daily.protein,
                      ),
                      const SizedBox(width: Dimens.spacing8),
                      macro(s.pointsFatLabel, palette.fat, daily.fat),
                    ],
                  ),
                  const SizedBox(height: Dimens.spacing8),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Dimens.spacing4),
                      Expanded(
                        child: Text(
                          s.onboardingPointsGuideOnly(
                            suggestion!.kcalGoal.round().toString(),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing16),
        ],
        Text(s.onboardingPointsMethodTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: Dimens.spacing8),
        Semantics(
          identifier: 'onboarding-points-method',
          child: SegmentedButton<PointsBudgetMethod>(
            segments: [
              ButtonSegment(
                value: PointsBudgetMethod.leanMass,
                label: Text(s.onboardingPointsMethodLeanMass),
              ),
              ButtonSegment(
                value: PointsBudgetMethod.appMacros,
                label: Text(s.onboardingPointsMethodCalories),
              ),
            ],
            selected: {_choice.method},
            onSelectionChanged: (v) => _set(_choice.copyWith(method: v.first)),
          ),
        ),
        const SizedBox(height: Dimens.spacing4),
        Text(
          _choice.method == PointsBudgetMethod.leanMass
              ? s.pointsMethodLeanMassSubtitle
              : s.pointsMethodAppMacrosSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Dimens.spacing16),
        Text(s.onboardingPointsMealsTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: Dimens.spacing8),
        Semantics(
          identifier: 'onboarding-points-meals',
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final n in OnboardingMealPresets.counts)
                ButtonSegment(value: n, label: Text('$n')),
            ],
            selected: {_choice.mealsPerDay},
            onSelectionChanged: (v) =>
                _set(_choice.copyWith(mealsPerDay: v.first)),
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        for (final slot in slots)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(mealSlotIcon(slot), size: 18),
                const SizedBox(width: Dimens.spacing8),
                Expanded(child: Text(mealSlotLabel(context, slot))),
                if (perSlot?[slot.id] case final p?)
                  Text(
                    '${format.points(p.total)} ${s.pointsShort}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: Dimens.spacing8),
        Semantics(
          identifier: 'onboarding-points-rebalance',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.pointsRebalanceTitle),
            subtitle: Text(s.pointsRebalanceHelp),
            value: _choice.rebalanceOverspend,
            onChanged: (v) => _set(_choice.copyWith(rebalanceOverspend: v)),
          ),
        ),
        Text(
          s.onboardingPointsLater,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
