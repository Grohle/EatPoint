import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/planner/data/planned_meal_logger.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

import 'planner_test_support.dart';

/// A diary in memory: entries by id.
class _Diary {
  final entries = <String, IntakeEntity>{};
  var next = 1;

  PlannedMealLogger logger() => PlannedMealLogger(
    intakesOn: (type, day) async => [
      for (final e in entries.values)
        if (e.type == type && e.dateTime == day) e,
    ],
    delete: (intake, day) async => entries.remove(intake.id),
  );

  void add(String name, double amount, IntakeTypeEntity type, DateTime day) {
    final id = 'i${next++}';
    entries[id] = IntakeEntity(
      id: id,
      unit: 'g',
      amount: amount,
      type: type,
      meal: plannerMeal(name),
      dateTime: day,
    );
  }
}

void main() {
  final day = DateTime(2026, 11, 28);
  final lunch = MealSlot.builtIn().firstWhere((s) => s.id == 'lunch');

  test('unlogging removes only what logging added', () async {
    final diary = _Diary()
      ..add('Pan', 40, IntakeTypeEntity.lunch, day); // logged by hand
    final plan = dayPlan(day, {
      'lunch': [plannedItem('Arroz', 80), plannedItem('Pollo', 150)],
    });
    final logger = diary.logger();

    final logged = await logger.log(
      plan,
      lunch,
      (item) async => diary.add(item.name, item.amount, lunch.baseType, day),
    );
    expect(logged.logged, contains('lunch'));
    expect(logged.loggedIntakes['lunch'], hasLength(2));
    expect(diary.entries, hasLength(3));

    final back = await logger.unlog(logged, lunch);
    expect(back.logged, isNot(contains('lunch')));
    expect(back.loggedIntakes, isEmpty);
    expect(diary.entries.values.map((e) => e.meal.name), ['Pan']);
    // The plan itself is kept.
    expect(back.itemsFor('lunch'), hasLength(2));
  });

  test('a meal logged before ids were kept is matched by food', () async {
    final diary = _Diary()
      ..add('Pan', 40, IntakeTypeEntity.lunch, day)
      ..add('Arroz', 80, IntakeTypeEntity.lunch, day)
      ..add('Arroz', 80, IntakeTypeEntity.lunch, day);
    final plan = dayPlan(day, {
      'lunch': [plannedItem('Arroz', 80)],
    }).withLogged('lunch', true);

    await diary.logger().unlog(plan, lunch);
    expect(
      diary.entries.values.map((e) => e.meal.name).toList(),
      ['Pan', 'Arroz'],
      reason: 'one entry per planned item, nothing else',
    );
  });

  test('logged entries survive a round trip through JSON', () {
    final plan = dayPlan(day, {
      'lunch': [plannedItem('Arroz', 80)],
    }).withLogged('lunch', true, intakeIds: ['a', 'b']);
    final back = DayPlan.fromJson(plan.toJson(), day);
    expect(back.loggedIntakes, {
      'lunch': ['a', 'b'],
    });
  });
}
