import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';

/// One of the meals the user eats in a day, such as "Breakfast" or
/// "Mid-morning".
///
/// The user can have as many meals as they like. The diary underneath only
/// knows four meal types, so each meal is stored under a [baseType] and
/// EatPoint remembers which meal every logged food belongs to (see
/// `MealSlotAssignments`).
///
/// The four built-in meals have the type's name as their [id] and no
/// [name], so they show the app's own translated label. Plans saved before
/// custom meals existed used those same ids, so they keep working.
class MealSlot {
  final String id;

  /// The name the user gave the meal. Null for a built-in meal, which shows
  /// the translated name of its [baseType].
  final String? name;

  final IntakeTypeEntity baseType;

  /// How much of each macro's daily points this meal gets, relative to the
  /// other meals. The shares of all meals don't need to add up to one.
  final MacroPoints share;

  const MealSlot({
    required this.id,
    required this.baseType,
    required this.share,
    this.name,
  });

  bool get isBuiltIn => name == null && id == baseType.name;

  MealSlot copyWith({
    String? Function()? name,
    IntakeTypeEntity? baseType,
    MacroPoints? share,
  }) => MealSlot(
    id: id,
    name: name != null ? name() : this.name,
    baseType: baseType ?? this.baseType,
    share: share ?? this.share,
  );

  /// The four built-in meals, in the order of a day, with [split] as their
  /// shares.
  static List<MealSlot> builtIn([
    Map<IntakeTypeEntity, MacroPoints> split =
        PointsBudgetCalc.defaultMealSplit,
  ]) => [
    for (final type in dayOrder)
      MealSlot(
        id: type.name,
        baseType: type,
        share: split[type] ?? PointsBudgetCalc.defaultMealSplit[type]!,
      ),
  ];

  /// The order the built-in meals come in during a day.
  static const dayOrder = [
    IntakeTypeEntity.breakfast,
    IntakeTypeEntity.lunch,
    IntakeTypeEntity.snack,
    IntakeTypeEntity.dinner,
  ];

  /// A new meal the user adds, stored as a snack unless they choose
  /// otherwise. Its share starts at the built-in snack's share.
  static MealSlot create({
    required String name,
    IntakeTypeEntity baseType = IntakeTypeEntity.snack,
    MacroPoints? share,
    DateTime? now,
  }) => MealSlot(
    id: 'm${(now ?? DateTime.now()).microsecondsSinceEpoch.toRadixString(36)}',
    name: name,
    baseType: baseType,
    share:
        share ??
        PointsBudgetCalc.defaultMealSplit[baseType] ??
        PointsBudgetCalc.defaultMealSplit[IntakeTypeEntity.snack]!,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'type': baseType.name,
    'share': {'carbs': share.carbs, 'protein': share.protein, 'fat': share.fat},
  };

  static MealSlot? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final typeName = json['type'];
    final rawShare = json['share'];
    if (id is! String || id.isEmpty || typeName is! String) return null;
    final type = IntakeTypeEntity.values
        .where((t) => t.name == typeName)
        .firstOrNull;
    if (type == null) return null;
    MacroPoints? share;
    if (rawShare is Map) {
      final c = rawShare['carbs'];
      final p = rawShare['protein'];
      final f = rawShare['fat'];
      if (c is num && p is num && f is num) {
        share = MacroPoints(
          carbs: c.toDouble().clamp(0, 100),
          protein: p.toDouble().clamp(0, 100),
          fat: f.toDouble().clamp(0, 100),
        );
      }
    }
    final name = json['name'];
    return MealSlot(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      baseType: type,
      share: share ?? PointsBudgetCalc.defaultMealSplit[type]!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MealSlot &&
      other.id == id &&
      other.name == name &&
      other.baseType == baseType &&
      other.share.carbs == share.carbs &&
      other.share.protein == share.protein &&
      other.share.fat == share.fat;

  @override
  int get hashCode => Object.hash(id, name, baseType, share.carbs);
}

/// Helpers over the list of meals of a day.
extension MealSlotList on List<MealSlot> {
  MealSlot? byId(String id) => where((s) => s.id == id).firstOrNull;

  /// The meal a food logged as [type] belongs to when nothing else says so:
  /// the first meal stored under that type.
  MealSlot? defaultFor(IntakeTypeEntity type) =>
      where((s) => s.baseType == type).firstOrNull;

  /// Each meal's budget out of [daily], split by the meals' shares in
  /// quarter points so the meals add up exactly to [daily].
  Map<String, MacroPoints> budgets(MacroPoints daily) =>
      PointsBudgetCalc.distribute(daily, {for (final s in this) s.id: s.share});

  /// Each meal's share of the day's minimum [fibrePoints], in quarter
  /// points. Fibre follows the meals' carb shares, where most of it is.
  Map<String, double> fibreTargets(double fibrePoints) => {
    for (final e in PointsBudgetCalc.distribute(
      MacroPoints(carbs: fibrePoints, protein: 0, fat: 0),
      {
        for (final s in this)
          s.id: MacroPoints(carbs: s.share.carbs, protein: 0, fat: 0),
      },
    ).entries)
      e.key: e.value.carbs,
  };
}
