import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';

import '../points/points_test_support.dart';

PlannedItem item(String id) =>
    PlannedItem(id: id, meal: pointsTestMeal(), amount: 150, unit: 'g');

void main() {
  final date = DateTime(2024, 5, 1);

  test('custom meal ids round-trip through JSON', () {
    final plan = DayPlan(
      date: date,
      meals: {
        'breakfast': [item('1')],
        'm1abc': [item('2'), item('3')],
      },
      logged: {'m1abc'},
    );
    final json = jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>;
    final back = DayPlan.fromJson(json, DateTime(2000));
    expect(back.date, date);
    expect(back.meals.keys.toSet(), {'breakfast', 'm1abc'});
    expect(back.itemsFor('m1abc').map((i) => i.id), ['2', '3']);
    expect(back.itemsFor('m1abc').first.amount, 150);
    expect(back.logged, {'m1abc'});
    expect(back.itemsFor('unknown'), isEmpty);
  });

  test('empty keys and ids are ignored on read', () {
    final back = DayPlan.fromJson({
      'date': '2024-05-01',
      'meals': {'': [], 'x': []},
      'logged': ['', 'x', 5],
    }, date);
    expect(back.meals.keys, ['x']);
    expect(back.logged, {'x'});
  });

  test('itemCount counts every food across meals', () {
    final plan = DayPlan(
      date: date,
      meals: {
        'a': [item('1'), item('2')],
        'm2': [item('3')],
        'c': const [],
      },
    );
    expect(plan.itemCount, 3);
    expect(DayPlan.empty(date).itemCount, 0);
  });

  group('fullyLogged', () {
    test('false for an empty plan', () {
      expect(DayPlan.empty(date).fullyLogged, isFalse);
      expect(DayPlan(date: date, meals: {'a': const []}).fullyLogged, isFalse);
    });

    test('true once every meal with food is logged', () {
      var plan = DayPlan(
        date: date,
        meals: {
          'a': [item('1')],
          'm2': [item('2')],
          'empty': const [],
        },
      );
      expect(plan.fullyLogged, isFalse);
      plan = plan.withLogged('a', true);
      expect(plan.fullyLogged, isFalse);
      plan = plan.withLogged('m2', true);
      expect(plan.fullyLogged, isTrue);
      plan = plan.withLogged('m2', false);
      expect(plan.fullyLogged, isFalse);
    });
  });

  test('withMeal and copyTo work with custom ids', () {
    final plan = DayPlan.empty(date).withMeal('mx', [item('1')]);
    expect(plan.itemsFor('mx').length, 1);
    final copy = plan.withLogged('mx', true).copyTo(DateTime(2024, 6, 1, 15));
    expect(copy.date, DateTime(2024, 6, 1));
    expect(copy.logged, isEmpty);
    expect(copy.itemsFor('mx').length, 1);
  });
}
