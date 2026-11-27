import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

bool isQuarter(double v) => ((v * 4) - (v * 4).round()).abs() < 1e-9;

void main() {
  group('MealSlot', () {
    test('builtIn order, ids and flags', () {
      final slots = MealSlot.builtIn();
      expect(
        [for (final s in slots) s.id],
        ['breakfast', 'lunch', 'snack', 'dinner'],
      );
      expect(slots.every((s) => s.isBuiltIn), isTrue);
      expect(slots.every((s) => s.name == null), isTrue);
      expect(
        slots[0].share,
        PointsBudgetCalc.defaultMealSplit[IntakeTypeEntity.breakfast],
      );
    });

    test('builtIn uses a custom split', () {
      const split = {
        IntakeTypeEntity.breakfast: MacroPoints(carbs: 1, protein: 2, fat: 3),
      };
      final slots = MealSlot.builtIn(split);
      expect(slots[0].share.protein, 2);
      // Missing types fall back to defaults.
      expect(
        slots[1].share,
        PointsBudgetCalc.defaultMealSplit[IntakeTypeEntity.lunch],
      );
    });

    test('isBuiltIn is false for named or differently-id slots', () {
      const share = MacroPoints(carbs: 1, protein: 1, fat: 1);
      expect(
        const MealSlot(
          id: 'lunch',
          baseType: IntakeTypeEntity.lunch,
          share: share,
          name: 'Lunch',
        ).isBuiltIn,
        isFalse,
      );
      expect(
        const MealSlot(
          id: 'x',
          baseType: IntakeTypeEntity.lunch,
          share: share,
        ).isBuiltIn,
        isFalse,
      );
    });

    test('create gives m-prefixed id, snack type and default share', () {
      final s = MealSlot.create(name: 'Elevenses', now: DateTime(2024, 1, 1));
      expect(s.id, startsWith('m'));
      expect(s.baseType, IntakeTypeEntity.snack);
      expect(s.name, 'Elevenses');
      expect(
        s.share,
        PointsBudgetCalc.defaultMealSplit[IntakeTypeEntity.snack],
      );
      expect(s.isBuiltIn, isFalse);
      final other = MealSlot.create(
        name: 'x',
        baseType: IntakeTypeEntity.lunch,
        now: DateTime(2024, 1, 1, 0, 0, 1),
      );
      expect(other.id, isNot(s.id));
      expect(
        other.share,
        PointsBudgetCalc.defaultMealSplit[IntakeTypeEntity.lunch],
      );
    });

    test('JSON round trip', () {
      final slot = MealSlot(
        id: 'm1',
        name: 'Brunch',
        baseType: IntakeTypeEntity.lunch,
        share: const MacroPoints(carbs: 0.5, protein: 0.25, fat: 1),
      );
      expect(MealSlot.fromJson(slot.toJson()), slot);
      for (final s in MealSlot.builtIn()) {
        final json = s.toJson();
        expect(json.containsKey('name'), isFalse);
        expect(MealSlot.fromJson(json), s);
      }
    });

    group('fromJson tolerance', () {
      Map<String, dynamic> valid() => {
        'id': 'a',
        'type': 'snack',
        'share': {'carbs': 1, 'protein': 2, 'fat': 3},
      };

      test('non-map -> null', () {
        expect(MealSlot.fromJson(null), isNull);
        expect(MealSlot.fromJson('x'), isNull);
        expect(MealSlot.fromJson([1]), isNull);
      });

      test('bad type -> null', () {
        expect(MealSlot.fromJson({...valid(), 'type': 'brunch'}), isNull);
        expect(MealSlot.fromJson({...valid(), 'type': 5}), isNull);
        expect(MealSlot.fromJson({...valid()}..remove('type')), isNull);
      });

      test('missing or empty id -> null', () {
        expect(MealSlot.fromJson({...valid()}..remove('id')), isNull);
        expect(MealSlot.fromJson({...valid(), 'id': ''}), isNull);
        expect(MealSlot.fromJson({...valid(), 'id': 3}), isNull);
      });

      test('bad share -> default share for the type', () {
        final expected =
            PointsBudgetCalc.defaultMealSplit[IntakeTypeEntity.snack];
        expect(MealSlot.fromJson({...valid(), 'share': 'x'})!.share, expected);
        expect(
          MealSlot.fromJson({
            ...valid(),
            'share': {'carbs': 1, 'protein': 'a', 'fat': 1},
          })!.share,
          expected,
        );
        expect(
          MealSlot.fromJson({...valid()}..remove('share'))!.share,
          expected,
        );
      });

      test('share values are clamped to 0..100', () {
        final s = MealSlot.fromJson({
          ...valid(),
          'share': {'carbs': -5, 'protein': 500, 'fat': 1},
        })!;
        expect(s.share.carbs, 0);
        expect(s.share.protein, 100);
        expect(s.share.fat, 1);
      });

      test('blank name -> null, name is trimmed', () {
        expect(MealSlot.fromJson({...valid(), 'name': '   '})!.name, isNull);
        expect(MealSlot.fromJson({...valid(), 'name': 7})!.name, isNull);
        expect(MealSlot.fromJson({...valid(), 'name': ' Tea '})!.name, 'Tea');
      });
    });

    test('copyWith can clear the name', () {
      final s = MealSlot.create(name: 'X', now: DateTime(2024));
      expect(s.copyWith(name: () => null).name, isNull);
      expect(s.copyWith().name, 'X');
      expect(
        s.copyWith(baseType: IntakeTypeEntity.dinner).baseType,
        IntakeTypeEntity.dinner,
      );
    });
  });

  group('MealSlotList', () {
    final slots = [
      ...MealSlot.builtIn(),
      MealSlot.create(name: 'Late snack', now: DateTime(2024, 1, 1)),
    ];

    test('byId', () {
      expect(slots.byId('lunch')!.baseType, IntakeTypeEntity.lunch);
      expect(slots.byId('nope'), isNull);
    });

    test('defaultFor returns the first slot of the type', () {
      expect(slots.defaultFor(IntakeTypeEntity.snack)!.id, 'snack');
      expect(
        [slots.last].defaultFor(IntakeTypeEntity.snack)!.name,
        'Late snack',
      );
      expect(
        slots.take(2).toList().defaultFor(IntakeTypeEntity.dinner),
        isNull,
      );
    });

    test('budgets add up exactly to daily per macro, in quarter steps', () {
      const daily = MacroPoints(carbs: 10.25, protein: 7.5, fat: 5.75);
      final b = slots.budgets(daily);
      expect(b.keys.toList(), [for (final s in slots) s.id]);
      var carbs = 0.0, protein = 0.0, fat = 0.0;
      for (final v in b.values) {
        carbs += v.carbs;
        protein += v.protein;
        fat += v.fat;
        expect(isQuarter(v.carbs), isTrue);
        expect(isQuarter(v.protein), isTrue);
        expect(isQuarter(v.fat), isTrue);
      }
      expect(carbs, closeTo(10.25, 1e-9));
      expect(protein, closeTo(7.5, 1e-9));
      expect(fat, closeTo(5.75, 1e-9));
    });

    test('budgets with a zero daily budget are all zero', () {
      final b = slots.budgets(MacroPoints.zero);
      expect(b.values.every((v) => v == MacroPoints.zero), isTrue);
    });
  });
}
