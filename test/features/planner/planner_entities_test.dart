import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';

import 'planner_test_support.dart';

void main() {
  group('DayPlan', () {
    final date = DateTime(2026, 11, 25);
    final plan = dayPlan(date, {
      IntakeTypeEntity.lunch: [plannedItem('Arroz', 150)],
      IntakeTypeEntity.dinner: [plannedItem('Leche', 200, unit: 'ml')],
    }).withLogged(IntakeTypeEntity.lunch, true);

    test('JSON round trip', () {
      final back = DayPlan.fromJson(
        jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>,
        DateTime(2000),
      );
      expect(back.date, date);
      expect(back.logged, {IntakeTypeEntity.lunch});
      expect(back.itemsFor(IntakeTypeEntity.lunch).single.name, 'Arroz');
      expect(back.itemsFor(IntakeTypeEntity.lunch).single.amount, 150);
      final milk = back.itemsFor(IntakeTypeEntity.dinner).single;
      expect(milk.unit, 'ml');
      expect(milk.amount, 200);
    });

    test('weekStart is the Monday of the week', () {
      // 2026-11-23 is a Monday.
      expect(DayPlan.weekStart(DateTime(2026, 11, 23)), DateTime(2026, 11, 23));
      expect(
        DayPlan.weekStart(DateTime(2026, 11, 25, 14)),
        DateTime(2026, 11, 23),
      );
      expect(DayPlan.weekStart(DateTime(2026, 11, 29)), DateTime(2026, 11, 23));
      expect(DayPlan.weekStart(DateTime(2026, 11, 30)), DateTime(2026, 11, 30));
    });

    test('dateKey is zero padded', () {
      expect(DayPlan.dateKey(DateTime(2026, 3, 4, 17)), '2026-03-04');
    });

    test('copyTo moves the plan and clears logged', () {
      final copy = plan.copyTo(DateTime(2026, 12, 2, 9));
      expect(copy.date, DateTime(2026, 12, 2));
      expect(copy.logged, isEmpty);
      expect(copy.itemsFor(IntakeTypeEntity.lunch), hasLength(1));
    });

    test('malformed JSON is tolerated', () {
      final back = DayPlan.fromJson({
        'date': 'not a date',
        'meals': {
          'lunch': [
            {'amount': 'x'},
            'junk',
            null,
          ],
          'dinner': 'nope',
        },
        'logged': ['lunch', 'brunch', 3],
      }, DateTime(2026, 11, 25, 8));
      expect(back.date, DateTime(2026, 11, 25));
      expect(back.itemsFor(IntakeTypeEntity.lunch), isEmpty);
      expect(back.logged, {IntakeTypeEntity.lunch});
      expect(
        DayPlan.fromJson({'meals': 5}, DateTime(2026, 1, 1)).isEmpty,
        true,
      );
    });
  });

  group('ShoppingListState', () {
    test('JSON round trip', () {
      const state = ShoppingListState(
        checked: {'a|g'},
        checkedBy: {'a|g': 'M'},
        manualItems: [
          ShoppingItem(
            key: 'manual|sal',
            name: 'Sal',
            amount: 500,
            unit: 'g',
            aisle: ShoppingAisle.pantry,
            manual: true,
          ),
        ],
      );
      final back = ShoppingListState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
      );
      expect(back.checked, {'a|g'});
      expect(back.checkedBy, {'a|g': 'M'});
      final item = back.manualItems.single;
      expect(item.key, 'manual|sal');
      expect(item.amount, 500);
      expect(item.aisle, ShoppingAisle.pantry);
      expect(item.manual, isTrue);
    });

    test('toggle and removeManual', () {
      var state = const ShoppingListState().toggle('k', by: 'M');
      expect(state.checked, {'k'});
      expect(state.checkedBy, {'k': 'M'});
      state = state.toggle('k');
      expect(state.checked, isEmpty);
      expect(state.checkedBy, isEmpty);
      state = state
          .addManual(
            const ShoppingItem(
              key: 'manual|x',
              name: 'X',
              amount: 0,
              unit: '',
              aisle: ShoppingAisle.other,
              manual: true,
            ),
          )
          .toggle('manual|x');
      state = state.removeManual('manual|x');
      expect(state.manualItems, isEmpty);
      expect(state.checked, isEmpty);
    });

    test('malformed JSON is tolerated', () {
      final back = ShoppingListState.fromJson({
        'checked': ['a', 3, null],
        'checkedBy': {'a': 'M', 'b': 4},
        'manual': [
          {'key': 'k', 'name': 'N', 'aisle': 'nonsense'},
          {'key': 1, 'name': 'bad'},
          'junk',
        ],
      });
      expect(back.checked, {'a'});
      expect(back.checkedBy, {'a': 'M'});
      expect(back.manualItems.single.aisle, ShoppingAisle.other);
      expect(back.manualItems.single.amount, 0);
      expect(ShoppingListState.fromJson({'checked': 'x'}).checked, isEmpty);
    });
  });

  group('PlannerReminderSettings', () {
    test('JSON round trip', () {
      const settings = PlannerReminderSettings(
        planWeek: (weekday: 7, hour: 18, minute: 0),
        shopping: (weekday: 1, hour: 19, minute: 30),
        prepare: (hour: 21, minute: 0),
        logAfterMinutes: 30,
      );
      final back = PlannerReminderSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(back.planWeek, settings.planWeek);
      expect(back.shopping, settings.shopping);
      expect(back.prepare, settings.prepare);
      expect(back.logAfterMinutes, 30);
    });

    test('off serialises to an empty map and back', () {
      expect(PlannerReminderSettings.off.toJson(), isEmpty);
      final back = PlannerReminderSettings.fromJson({});
      expect(back.planWeek, isNull);
      expect(back.logAfterMinutes, isNull);
    });

    test('malformed and out-of-range values are tolerated', () {
      final back = PlannerReminderSettings.fromJson({
        'planWeek': [9, 30, 99],
        'shopping': ['a', 1, 2],
        'prepare': [1],
        'logAfterMinutes': 1,
      });
      expect(back.planWeek, (weekday: 7, hour: 23, minute: 59));
      expect(back.shopping, isNull);
      expect(back.prepare, isNull);
      expect(back.logAfterMinutes, 5);
      expect(
        PlannerReminderSettings.fromJson({
          'logAfterMinutes': 'x',
        }).logAfterMinutes,
        isNull,
      );
    });
  });
}
