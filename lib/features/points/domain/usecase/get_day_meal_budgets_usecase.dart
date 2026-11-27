import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_rebalance_calc.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_meal_points_usage_usecase.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';

/// What the user has to eat with on one day, meal by meal: the planned
/// budget of each meal, what was logged in it, and the budget that applies
/// now that earlier meals may have gone over.
class DayMealBudgets {
  final PointsBudgetResult budget;
  final List<MealSlot> slots;

  /// Each meal's budget before any rebalancing.
  final Map<String, MacroPoints> base;

  /// What was logged in each meal.
  final Map<String, MacroPoints> used;

  /// Each meal's budget after an overspend in an earlier meal was taken off
  /// it. Equal to [base] when rebalancing is off.
  final Map<String, MacroPoints> effective;

  /// Travel mode asks to count against the daily budget only.
  final bool dailyOnly;

  const DayMealBudgets({
    required this.budget,
    required this.slots,
    required this.base,
    required this.used,
    required this.effective,
    required this.dailyOnly,
  });

  MacroPoints get daily => budget.daily;

  MacroPoints get usedTotal =>
      used.values.fold(MacroPoints.zero, (sum, p) => sum + p);

  /// Whether [slotId]'s budget was lowered because an earlier meal went
  /// over.
  bool isAdjusted(String slotId) {
    final b = base[slotId];
    final e = effective[slotId];
    return b != null && e != null && (b.total - e.total).abs() > 0.001;
  }
}

class GetDayMealBudgetsUsecase {
  final GetPointsBudgetUsecase _budget;
  final GetMealPointsUsageUsecase _usage;

  GetDayMealBudgetsUsecase(this._budget, this._usage);

  Future<DayMealBudgets> forDay(DateTime day) async {
    final budget = await _budget.getBudget();
    final slots = budget.slots.isEmpty ? MealSlot.builtIn() : budget.slots;
    final base = budget.perSlot.isEmpty
        ? slots.budgets(budget.daily)
        : budget.perSlot;
    final used = await _usage.usedPerSlot(day, slots);
    final effective = budget.settings.rebalanceOverspend
        ? PointsRebalanceCalc.rebalance(
            order: [for (final s in slots) s.id],
            budgets: base,
            used: used,
          )
        : base;
    return DayMealBudgets(
      budget: budget,
      slots: slots,
      base: base,
      used: used,
      effective: effective,
      dailyOnly: TravelModeGate.dailyBudgetOnly,
    );
  }
}
