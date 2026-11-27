import 'package:opennutritracker/core/utils/calc/points_calc.dart';

/// Moves what a meal went over its budget onto the meals still ahead in the
/// day, so the day as a whole stays on budget.
///
/// Works one macro at a time: when a meal's logged carb points are above its
/// carb budget, the excess is taken off the carb budgets of the later meals,
/// in proportion to what each of them still has, in quarter points. A later
/// meal's budget never goes below zero; whatever cannot be absorbed stays as
/// an overspend of the day. Earlier meals are never touched, and a meal that
/// came in under budget gives nothing away.
class PointsRebalanceCalc {
  PointsRebalanceCalc._();

  /// [order] lists the meals of the day in order; [budgets] and [used] are
  /// keyed by the same ids. Returns each meal's adjusted budget.
  static Map<String, MacroPoints> rebalance({
    required List<String> order,
    required Map<String, MacroPoints> budgets,
    required Map<String, MacroPoints> used,
  }) {
    final carbs = _macro(
      order,
      [for (final id in order) budgets[id]?.carbs ?? 0],
      [for (final id in order) used[id]?.carbs ?? 0],
    );
    final protein = _macro(
      order,
      [for (final id in order) budgets[id]?.protein ?? 0],
      [for (final id in order) used[id]?.protein ?? 0],
    );
    final fat = _macro(
      order,
      [for (final id in order) budgets[id]?.fat ?? 0],
      [for (final id in order) used[id]?.fat ?? 0],
    );
    return {
      for (var i = 0; i < order.length; i++)
        order[i]: MacroPoints(
          carbs: carbs[i],
          protein: protein[i],
          fat: fat[i],
        ),
    };
  }

  static List<double> _macro(
    List<String> order,
    List<double> budgets,
    List<double> used,
  ) {
    const step = PointsCalc.pointStep;
    // Work in whole quarter points so the result never drifts.
    final adjusted = [for (final b in budgets) (b / step).round()];
    final spent = [for (final u in used) (u / step).round()];
    for (var i = 0; i < order.length; i++) {
      var over = spent[i] - adjusted[i];
      if (over <= 0) continue;
      final later = [for (var j = i + 1; j < order.length; j++) j];
      final room = [for (final j in later) adjusted[j] < 0 ? 0 : adjusted[j]];
      final totalRoom = room.fold<int>(0, (a, b) => a + b);
      if (totalRoom <= 0) continue;
      if (over >= totalRoom) {
        for (final j in later) {
          adjusted[j] = 0;
        }
        continue;
      }
      // Largest-remainder split of `over` in proportion to each later
      // meal's room; ties go to the earlier meal.
      final ideal = [for (final r in room) over * r / totalRoom];
      final take = [for (final x in ideal) x.floor()];
      over -= take.fold<int>(0, (a, b) => a + b);
      final byRemainder = List<int>.generate(later.length, (k) => k)
        ..sort((a, b) {
          final c = (ideal[b] - take[b]).compareTo(ideal[a] - take[a]);
          return c != 0 ? c : a.compareTo(b);
        });
      for (final k in byRemainder) {
        if (over <= 0) break;
        if (take[k] < room[k]) {
          take[k]++;
          over--;
        }
      }
      for (var k = 0; k < later.length; k++) {
        adjusted[later[k]] -= take[k];
      }
    }
    return [for (final a in adjusted) a * step];
  }
}
