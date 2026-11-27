import 'dart:math' as math;

import 'package:opennutritracker/core/utils/calc/points_calc.dart';

/// Chooses amounts for the foods of a meal so that, together, they fill the
/// meal's carb, protein and fat points as closely as possible.
///
/// Foods whose amount is already known keep it; their points are taken off
/// the budget first. The free foods share what is left: the solver looks
/// for non-negative amounts that minimise the squared distance to each
/// macro's budget, with a light pull towards giving every free food a
/// similar number of points so none of them is dropped to zero just
/// because another food fits a macro better. Amounts are rounded to
/// practical grams (see [PointsCalc.roundPracticalGrams]).
class MenuAmountSolver {
  MenuAmountSolver._();

  /// Smallest amount a food gets when it is in the meal at all, in grams.
  static const minGrams = 5.0;

  /// Largest amount the solver hands out for one food, in grams.
  static const maxGrams = 600.0;

  /// [per100] holds each free food's points per 100 g; [budget] is what the
  /// free foods should add up to (the meal's budget minus the fixed foods).
  /// Returns grams per food, in the same order.
  static List<double> solve({
    required List<MacroPoints> per100,
    required MacroPoints budget,
    int iterations = 2000,
  }) {
    final n = per100.length;
    if (n == 0) return const [];
    final target = [
      math.max(0.0, budget.carbs),
      math.max(0.0, budget.protein),
      math.max(0.0, budget.fat),
    ];
    final a = [
      for (final p in per100) [p.carbs, p.protein, p.fat],
    ];
    final totalTarget = target.reduce((x, y) => x + y);
    if (totalTarget <= 0) {
      return List.filled(n, minGrams);
    }
    // Start from an equal share of the total points for every food.
    final x = [
      for (final row in a)
        row.reduce((p, q) => p + q) <= 0
            ? 0.0
            : (totalTarget / n) / row.reduce((p, q) => p + q),
    ];
    // Regularisation weight towards equal points per food.
    const lambda = 0.02;
    // Step from the largest row norm so the descent stays stable.
    var lipschitz = 0.0;
    var maxRowTotal = 0.0;
    for (final row in a) {
      lipschitz += row.fold<double>(0, (s, v) => s + v * v);
      maxRowTotal = math.max(maxRowTotal, row.reduce((p, q) => p + q));
    }
    lipschitz = 2 * (lipschitz + lambda * maxRowTotal * maxRowTotal);
    final step = lipschitz <= 0 ? 0.0 : 1 / lipschitz;
    final equalShare = totalTarget / n;

    for (var it = 0; it < iterations; it++) {
      final residual = List<double>.filled(3, 0);
      for (var m = 0; m < 3; m++) {
        var sum = 0.0;
        for (var i = 0; i < n; i++) {
          sum += a[i][m] * x[i];
        }
        residual[m] = sum - target[m];
      }
      for (var i = 0; i < n; i++) {
        final rowTotal = a[i].reduce((p, q) => p + q);
        var grad = 0.0;
        for (var m = 0; m < 3; m++) {
          grad += 2 * a[i][m] * residual[m];
        }
        grad += 2 * lambda * rowTotal * (rowTotal * x[i] - equalShare);
        x[i] = math.max(0.0, x[i] - step * grad);
      }
    }
    return [
      for (var i = 0; i < n; i++)
        a[i].every((v) => v <= 0)
            ? minGrams
            : PointsCalc.roundPracticalGrams(
                (x[i] * 100).clamp(minGrams, maxGrams),
              ),
    ];
  }
}
