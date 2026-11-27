import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';

PointsSettings roundTrip(PointsSettings s) => PointsSettings.fromJson(
  jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
);

void main() {
  final custom = [
    MealSlot.builtIn().first,
    MealSlot.create(name: 'Mid-morning', now: DateTime(2024, 1, 1)),
    MealSlot.builtIn().last,
  ];

  test('mealSlots round trip', () {
    final s = roundTrip(PointsSettings(mealSlots: custom));
    expect(s.mealSlots, custom);
  });

  test('null mealSlots are not written and read back null', () {
    final json = const PointsSettings().toJson();
    expect(json.containsKey('mealSlots'), isFalse);
    expect(PointsSettings.fromJson(json).mealSlots, isNull);
  });

  test('duplicate slot ids are dropped on read, first wins', () {
    final s = PointsSettings.fromJson({
      'mealSlots': [
        {'id': 'a', 'type': 'lunch', 'name': 'First'},
        {'id': 'a', 'type': 'dinner', 'name': 'Second'},
        {'id': 'b', 'type': 'snack'},
      ],
    });
    expect([for (final m in s.mealSlots!) m.id], ['a', 'b']);
    expect(s.mealSlots!.first.name, 'First');
  });

  test('invalid slots are skipped; empty result becomes null', () {
    expect(PointsSettings.fromJson({'mealSlots': []}).mealSlots, isNull);
    expect(
      PointsSettings.fromJson({
        'mealSlots': [
          {'id': '', 'type': 'lunch'},
          'junk',
        ],
      }).mealSlots,
      isNull,
    );
    expect(PointsSettings.fromJson({'mealSlots': 'x'}).mealSlots, isNull);
  });

  test('effectiveMealSlots uses the user list when set', () {
    expect(PointsSettings(mealSlots: custom).effectiveMealSlots, custom);
  });

  test('effectiveMealSlots falls back to built-in with effectiveMealSplit', () {
    expect(const PointsSettings().effectiveMealSlots, MealSlot.builtIn());
    final split = {
      for (final t in IntakeTypeEntity.values)
        t: const MacroPoints(carbs: 1, protein: 1, fat: 1),
    };
    final slots = PointsSettings(mealSplit: split).effectiveMealSlots;
    expect(slots.length, 4);
    expect(slots.every((s) => s.share.carbs == 1), isTrue);
    // An empty list also falls back.
    expect(
      const PointsSettings(mealSlots: []).effectiveMealSlots,
      MealSlot.builtIn(),
    );
  });

  test('rebalanceOverspend defaults to true and round trips', () {
    expect(const PointsSettings().rebalanceOverspend, isTrue);
    expect(PointsSettings.fromJson({}).rebalanceOverspend, isTrue);
    expect(
      PointsSettings.fromJson({'rebalanceOverspend': 'no'}).rebalanceOverspend,
      isTrue,
    );
    final off = roundTrip(const PointsSettings(rebalanceOverspend: false));
    expect(off.rebalanceOverspend, isFalse);
    expect(
      const PointsSettings()
          .copyWith(rebalanceOverspend: false)
          .rebalanceOverspend,
      isFalse,
    );
  });

  test('copyWith can set and clear mealSlots', () {
    final s = const PointsSettings().copyWith(mealSlots: () => custom);
    expect(s.mealSlots, custom);
    expect(s.copyWith(mealSlots: () => null).mealSlots, isNull);
    expect(s.copyWith().mealSlots, custom);
  });
}
