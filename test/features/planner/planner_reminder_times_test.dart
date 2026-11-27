import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/planner/data/planner_reminder_service.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

MealSlot custom(String id, [IntakeTypeEntity t = IntakeTypeEntity.snack]) =>
    MealSlot(
      id: id,
      name: id,
      baseType: t,
      share: const MacroPoints(carbs: 1, protein: 1, fat: 1),
    );

List<String> fmt(List<MealSlot> meals) => [
  for (final t in PlannerReminderService.timesFor(meals))
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
];

void main() {
  test('built-in meals sit at their usual times', () {
    expect(fmt(MealSlot.builtIn()), ['09:00', '14:30', '18:00', '21:30']);
  });

  test('empty list gives empty result', () {
    expect(PlannerReminderService.timesFor([]), isEmpty);
  });

  test('custom meal sits midway between its neighbours', () {
    final b = MealSlot.builtIn();
    // 09:00 .. 14:30 -> 11:45
    expect(fmt([b[0], custom('x'), b[1]]), ['09:00', '11:45', '14:30']);
  });

  test('several custom meals are spread evenly', () {
    final b = MealSlot.builtIn();
    // 540 .. 870 in thirds: 650 (10:50), 760 (12:40)
    expect(fmt([b[0], custom('x'), custom('y'), b[1]]), [
      '09:00',
      '10:50',
      '12:40',
      '14:30',
    ]);
  });

  test('before the first built-in meal counts from 07:00', () {
    final b = MealSlot.builtIn();
    // 07:00 .. 09:00 midway -> 08:00
    expect(fmt([custom('x'), b[0]]).first, '08:00');
  });

  test('after the last built-in meal counts towards 23:00', () {
    final b = MealSlot.builtIn();
    // 21:30 .. 23:00 midway -> 22:15
    expect(fmt([b[3], custom('x')]), ['21:30', '22:15']);
  });

  test('only custom meals spread between 07:00 and 23:00', () {
    expect(fmt([custom('a'), custom('b'), custom('c')]), [
      '11:00',
      '15:00',
      '19:00',
    ]);
  });

  test('a renamed built-in id is treated as custom', () {
    final b = MealSlot.builtIn();
    final renamed = b[1].copyWith(name: () => 'Midday');
    expect(renamed.isBuiltIn, isFalse);
    expect(fmt([b[0], renamed, b[2]]), ['09:00', '13:30', '18:00']);
  });

  test('times come out in non-decreasing order for a normal day', () {
    final b = MealSlot.builtIn();
    final meals = [
      custom('a'),
      b[0],
      custom('b'),
      custom('c'),
      b[1],
      b[2],
      custom('d'),
      b[3],
      custom('e'),
    ];
    final mins = [
      for (final t in PlannerReminderService.timesFor(meals))
        t.hour * 60 + t.minute,
    ];
    expect(mins.length, meals.length);
    for (var i = 1; i < mins.length; i++) {
      expect(mins[i], greaterThanOrEqualTo(mins[i - 1]));
    }
    expect(mins.every((m) => m >= 0 && m < 24 * 60), isTrue);
  });
}
