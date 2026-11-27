import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/points/data/meal_slot_assignments.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

import '../../helpers/fake_hive_db_provider.dart';
import 'points_test_support.dart';

IntakeEntity intake(String id, IntakeTypeEntity type, {DateTime? at}) =>
    IntakeEntity(
      id: id,
      unit: 'g',
      amount: 100,
      type: type,
      meal: pointsTestMeal(),
      dateTime: at ?? DateTime(2024, 5, 1, 12),
    );

void main() {
  late MemoryStringBox box;
  late MealSlotAssignments store;
  const share = MacroPoints(carbs: 1, protein: 1, fat: 1);
  final mid = const MealSlot(
    id: 'mid',
    name: 'Mid-morning',
    baseType: IntakeTypeEntity.snack,
    share: share,
  );
  final afternoon = const MealSlot(
    id: 'aft',
    name: 'Afternoon',
    baseType: IntakeTypeEntity.snack,
    share: share,
  );
  final slots = [
    MealSlot.builtIn()[0],
    mid,
    MealSlot.builtIn()[1],
    afternoon,
    MealSlot.builtIn()[3],
  ];

  setUp(() {
    box = MemoryStringBox();
    store = MealSlotAssignments(FakeHiveDBProvider(pointsSettingsBox: box));
    MealSlotContext.clear();
  });

  tearDown(MealSlotContext.clear);

  group('assign / slotIdOf', () {
    test('unassigned is null', () {
      expect(store.slotIdOf(intake('i1', IntakeTypeEntity.snack)), isNull);
    });

    test('assign stores per day and bumps revision', () async {
      final a = intake('i1', IntakeTypeEntity.snack);
      final rev = store.revision.value;
      await store.assign(a, 'aft');
      expect(store.slotIdOf(a), 'aft');
      expect(store.revision.value, rev + 1);
      expect(box.data.keys, ['slots:2024-05-01']);
      // Same id on another day is separate.
      final other = intake(
        'i1',
        IntakeTypeEntity.snack,
        at: DateTime(2024, 5, 2),
      );
      expect(store.slotIdOf(other), isNull);
    });

    test('assigning the same slot again does not write or bump', () async {
      final a = intake('i1', IntakeTypeEntity.snack);
      await store.assign(a, 'aft');
      final rev = store.revision.value;
      await store.assign(a, 'aft');
      expect(store.revision.value, rev);
    });

    test('reassign overwrites and keeps other intakes', () async {
      final a = intake('i1', IntakeTypeEntity.snack);
      final b = intake('i2', IntakeTypeEntity.snack);
      await store.assign(a, 'mid');
      await store.assign(b, 'aft');
      await store.assign(a, 'aft');
      expect(store.slotIdOf(a), 'aft');
      expect(store.slotIdOf(b), 'aft');
    });

    test('unreadable stored JSON is treated as empty', () {
      box.data['slots:2024-05-01'] = '{not json';
      expect(store.slotIdOf(intake('i1', IntakeTypeEntity.snack)), isNull);
    });

    test('cache picks up external writes to the box', () async {
      final a = intake('i1', IntakeTypeEntity.snack);
      await store.assign(a, 'mid');
      expect(store.slotIdOf(a), 'mid');
      box.data['slots:2024-05-01'] = '{"i1":"aft"}';
      expect(store.slotIdOf(a), 'aft');
      box.data.remove('slots:2024-05-01');
      expect(store.slotIdOf(a), isNull);
    });
  });

  group('resolve', () {
    test('assigned slot is used', () async {
      final a = intake('i1', IntakeTypeEntity.snack);
      await store.assign(a, 'aft');
      expect(store.resolve(a, slots), afternoon);
    });

    test('unassigned goes to the first slot of its type', () {
      expect(store.resolve(intake('i1', IntakeTypeEntity.snack), slots), mid);
    });

    test('removed slot falls back to first slot of the same type', () async {
      final a = intake('i1', IntakeTypeEntity.snack);
      await store.assign(a, 'gone');
      expect(store.resolve(a, slots), mid);
    });

    test('slot whose baseType changed falls back to default', () async {
      final a = intake('i1', IntakeTypeEntity.snack);
      await store.assign(a, 'aft');
      final changed = [
        for (final s in slots)
          if (s.id == 'aft')
            s.copyWith(baseType: IntakeTypeEntity.dinner)
          else
            s,
      ];
      expect(store.resolve(a, changed), mid);
    });

    test('no slot of the type -> null', () {
      final only = [MealSlot.builtIn()[0]];
      expect(
        store.resolve(intake('i1', IntakeTypeEntity.dinner), only),
        isNull,
      );
    });
  });

  group('group', () {
    test('groups by slot in slot order and reports orphans', () async {
      final b = intake('b', IntakeTypeEntity.breakfast);
      final s1 = intake('s1', IntakeTypeEntity.snack);
      final s2 = intake('s2', IntakeTypeEntity.snack);
      final d = intake('d', IntakeTypeEntity.dinner);
      await store.assign(s2, 'aft');
      final reduced = [
        for (final s in slots)
          if (s.id != 'dinner') s,
      ];
      final g = store.group([b, s1, s2, d], reduced);
      expect(g.bySlot.keys.toList(), [for (final s in reduced) s.id]);
      expect(g.bySlot['breakfast'], [b]);
      expect(g.bySlot['mid'], [s1]);
      expect(g.bySlot['aft'], [s2]);
      expect(g.bySlot['lunch'], isEmpty);
      expect(g.orphans, {
        IntakeTypeEntity.dinner: [d],
      });
    });

    test('empty input gives empty slot lists', () {
      final g = store.group(const [], slots);
      expect(g.bySlot.length, slots.length);
      expect(g.orphans, isEmpty);
    });
  });

  group('MealSlotContext', () {
    test('onIntakeAdded assigns when the pending type matches', () async {
      MealSlotContext.select(afternoon);
      final a = intake('i1', IntakeTypeEntity.snack);
      MealSlotContext.onIntakeAdded(a, store);
      await Future<void>.delayed(Duration.zero);
      expect(store.slotIdOf(a), 'aft');
    });

    test('onIntakeAdded ignores a different type', () async {
      MealSlotContext.select(afternoon);
      final a = intake('i1', IntakeTypeEntity.lunch);
      MealSlotContext.onIntakeAdded(a, store);
      await Future<void>.delayed(Duration.zero);
      expect(store.slotIdOf(a), isNull);
    });

    test('onIntakeAdded does nothing without a pending slot', () async {
      final a = intake('i1', IntakeTypeEntity.snack);
      MealSlotContext.onIntakeAdded(a, store);
      await Future<void>.delayed(Duration.zero);
      expect(box.data, isEmpty);
    });

    test('run selects during the body and clears afterwards', () async {
      final result = await MealSlotContext.run(afternoon, () async {
        expect(MealSlotContext.pending?.slotId, 'aft');
        expect(MealSlotContext.pending?.type, IntakeTypeEntity.snack);
        return 42;
      });
      expect(result, 42);
      expect(MealSlotContext.pending, isNull);
    });

    test('run clears even when the body throws', () async {
      await expectLater(
        MealSlotContext.run<void>(afternoon, () async => throw StateError('x')),
        throwsStateError,
      );
      expect(MealSlotContext.pending, isNull);
    });
  });
}
