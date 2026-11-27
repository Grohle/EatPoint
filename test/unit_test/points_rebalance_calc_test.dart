import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_rebalance_calc.dart';

MacroPoints c(double v) => MacroPoints(carbs: v, protein: 0, fat: 0);

bool isQuarter(double v) => ((v * 4) - (v * 4).round()).abs() < 1e-9;

void main() {
  const order = ['a', 'b', 'c'];

  Map<String, MacroPoints> run(
    List<double> budgets,
    List<double> used, {
    List<String> ids = order,
  }) => PointsRebalanceCalc.rebalance(
    order: ids,
    budgets: {for (var i = 0; i < ids.length; i++) ids[i]: c(budgets[i])},
    used: {for (var i = 0; i < ids.length; i++) ids[i]: c(used[i])},
  );

  group('PointsRebalanceCalc', () {
    test('no change when nobody is over', () {
      final r = run([4, 3, 2], [4, 1, 0]);
      expect([for (final id in order) r[id]!.carbs], [4, 3, 2]);
    });

    test('excess is taken off later meals in proportion to their room', () {
      // Over by 2 points; later budgets 3 and 1 -> 1.5 and 0.5 taken.
      final r = run([2, 3, 1], [4, 0, 0]);
      expect(r['a']!.carbs, 2);
      expect(r['b']!.carbs, 1.5);
      expect(r['c']!.carbs, 0.5);
    });

    test('earlier meals are untouched', () {
      final r = run([3, 2, 2], [0, 4, 0]);
      expect(r['a']!.carbs, 3);
      expect(r['b']!.carbs, 2);
      expect(r['c']!.carbs, 0);
    });

    test('meal under budget gives nothing away', () {
      final r = run([3, 2, 2], [1, 0, 0]);
      expect(r['b']!.carbs, 2);
      expect(r['c']!.carbs, 2);
    });

    test('overspend larger than all later room zeroes later meals', () {
      final r = run([1, 1, 1], [10, 0, 0]);
      expect(r['a']!.carbs, 1);
      expect(r['b']!.carbs, 0);
      expect(r['c']!.carbs, 0);
    });

    test('never goes below zero when cascading overspends', () {
      final r = run([1, 1, 1], [5, 5, 5]);
      for (final id in order) {
        expect(r[id]!.carbs, greaterThanOrEqualTo(0));
      }
    });

    test('last meal over changes nothing', () {
      final r = run([2, 2, 2], [0, 0, 9]);
      expect([for (final id in order) r[id]!.carbs], [2, 2, 2]);
    });

    test('results are quarter-point multiples', () {
      final r = run([1, 1.25, 0.75], [2.25, 0, 0]);
      for (final id in order) {
        expect(isQuarter(r[id]!.carbs), isTrue);
      }
      // 1.25 over (5 quarters) split 5:3 -> 3.125 / 1.875 -> 3+1 / 2... total 5
      final taken = (1.25 + 0.75) - (r['b']!.carbs + r['c']!.carbs);
      expect(taken, closeTo(1.25, 1e-9));
    });

    test('macros are independent', () {
      final r = PointsRebalanceCalc.rebalance(
        order: ['a', 'b'],
        budgets: {
          'a': const MacroPoints(carbs: 1, protein: 1, fat: 1),
          'b': const MacroPoints(carbs: 4, protein: 4, fat: 4),
        },
        used: {
          'a': const MacroPoints(carbs: 2, protein: 0, fat: 0.5),
          'b': MacroPoints.zero,
        },
      );
      expect(r['b']!.carbs, 3);
      expect(r['b']!.protein, 4);
      expect(r['b']!.fat, 4);
    });

    test('missing ids in maps are treated as zero', () {
      final r = PointsRebalanceCalc.rebalance(
        order: ['a', 'b'],
        budgets: {'b': c(2)},
        used: {'a': c(1)},
      );
      expect(r['a']!.carbs, 0);
      expect(r['b']!.carbs, 1);
    });

    test('empty order gives empty result', () {
      expect(
        PointsRebalanceCalc.rebalance(order: [], budgets: {}, used: {}),
        isEmpty,
      );
    });

    test('property: first-meal excess is absorbed by later meals', () {
      final rnd = Random(42);
      for (var iter = 0; iter < 400; iter++) {
        final n = 2 + rnd.nextInt(5);
        final ids = [for (var i = 0; i < n; i++) 'm$i'];
        final budgetQ = [for (var i = 0; i < n; i++) rnd.nextInt(40)];
        final overQ = rnd.nextInt(80);
        final usedQ = [budgetQ[0] + overQ, for (var i = 1; i < n; i++) 0];
        final budgets = [for (final q in budgetQ) q * 0.25];
        final used = [for (final q in usedQ) q * 0.25];
        final r = run(budgets, used, ids: ids);

        final roomQ = budgetQ.skip(1).fold<int>(0, (a, b) => a + b);
        final laterAfterQ = [
          for (var i = 1; i < n; i++) (r[ids[i]]!.carbs * 4).round(),
        ].fold<int>(0, (a, b) => a + b);
        expect(
          roomQ - laterAfterQ,
          min(overQ, roomQ),
          reason: 'iter $iter budgets $budgetQ over $overQ',
        );
        expect(r[ids[0]]!.carbs, budgets[0]);
        for (var i = 1; i < n; i++) {
          final v = r[ids[i]]!.carbs;
          expect(v, greaterThanOrEqualTo(0));
          expect(isQuarter(v), isTrue);
          expect(v, lessThanOrEqualTo(budgets[i] + 1e-9));
        }
      }
    });

    test('property: arbitrary usage keeps invariants', () {
      final rnd = Random(7);
      for (var iter = 0; iter < 400; iter++) {
        final n = 1 + rnd.nextInt(6);
        final ids = [for (var i = 0; i < n; i++) 'm$i'];
        final budgets = [for (var i = 0; i < n; i++) rnd.nextInt(40) * 0.25];
        final used = [for (var i = 0; i < n; i++) rnd.nextInt(60) * 0.25];
        final r = run(budgets, used, ids: ids);
        expect(r[ids[0]]!.carbs, budgets[0]);
        for (var i = 0; i < n; i++) {
          final v = r[ids[i]]!.carbs;
          expect(v, greaterThanOrEqualTo(0), reason: 'iter $iter');
          expect(isQuarter(v), isTrue, reason: 'iter $iter');
          expect(v, lessThanOrEqualTo(budgets[i] + 1e-9), reason: 'iter $iter');
        }
      }
    });
  });
}
