import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';

/// One food planned for a meal: a snapshot of the food and the amount in
/// grams (or ml for liquids).
class PlannedItem {
  final String id;
  final MealEntity meal;
  final double amount;

  /// 'g' or 'ml'.
  final String unit;

  const PlannedItem({
    required this.id,
    required this.meal,
    required this.amount,
    required this.unit,
  });

  MacroPoints get points => meal.nutriments.macroPointsFor(amount);

  String get name => meal.name ?? '';

  PlannedItem copyWith({double? amount}) => PlannedItem(
    id: id,
    meal: meal,
    amount: amount ?? this.amount,
    unit: unit,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'meal': MealDBO.fromMealEntity(meal).toJson(),
    'amount': amount,
    'unit': unit,
  };

  static PlannedItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawMeal = json['meal'];
    final amount = json['amount'];
    if (rawMeal is! Map || amount is! num) return null;
    try {
      return PlannedItem(
        id: json['id'] as String? ?? '',
        meal: MealEntity.fromMealDBO(
          MealDBO.fromJson(Map<String, dynamic>.from(rawMeal)),
        ),
        amount: amount.toDouble(),
        unit: json['unit'] as String? ?? 'g',
      );
    } catch (_) {
      return null;
    }
  }
}

/// The plan for one day: the foods planned per meal and which meals were
/// already logged from the plan.
class DayPlan {
  /// Local date, time part zero.
  final DateTime date;
  final Map<IntakeTypeEntity, List<PlannedItem>> meals;
  final Set<IntakeTypeEntity> logged;

  const DayPlan({
    required this.date,
    this.meals = const {},
    this.logged = const {},
  });

  factory DayPlan.empty(DateTime date) => DayPlan(date: dateOnly(date));

  List<PlannedItem> itemsFor(IntakeTypeEntity type) => meals[type] ?? const [];

  MacroPoints pointsFor(IntakeTypeEntity type) =>
      itemsFor(type).fold(MacroPoints.zero, (sum, i) => sum + i.points);

  MacroPoints get totalPoints =>
      meals.keys.fold(MacroPoints.zero, (sum, t) => sum + pointsFor(t));

  bool get isEmpty => meals.values.every((items) => items.isEmpty);

  DayPlan withMeal(IntakeTypeEntity type, List<PlannedItem> items) =>
      DayPlan(date: date, meals: {...meals, type: items}, logged: logged);

  DayPlan withLogged(IntakeTypeEntity type, bool value) => DayPlan(
    date: date,
    meals: meals,
    logged: value ? {...logged, type} : ({...logged}..remove(type)),
  );

  /// The same plan on another date, with nothing marked as logged.
  DayPlan copyTo(DateTime other) =>
      DayPlan(date: dateOnly(other), meals: meals, logged: const {});

  Map<String, dynamic> toJson() => {
    'date': dateKey(date),
    'meals': {
      for (final e in meals.entries)
        e.key.name: [for (final i in e.value) i.toJson()],
    },
    'logged': [for (final t in logged) t.name],
  };

  static DayPlan fromJson(Map<String, dynamic> json, DateTime fallbackDate) {
    final date = DateTime.tryParse(json['date'] as String? ?? '');
    final meals = <IntakeTypeEntity, List<PlannedItem>>{};
    final rawMeals = json['meals'];
    if (rawMeals is Map) {
      for (final type in IntakeTypeEntity.values) {
        final raw = rawMeals[type.name];
        if (raw is List) {
          meals[type] = raw
              .map(PlannedItem.fromJson)
              .whereType<PlannedItem>()
              .toList();
        }
      }
    }
    final rawLogged = json['logged'];
    return DayPlan(
      date: dateOnly(date ?? fallbackDate),
      meals: meals,
      logged: {
        if (rawLogged is List)
          for (final name in rawLogged)
            for (final t in IntakeTypeEntity.values)
              if (t.name == name) t,
      },
    );
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String dateKey(DateTime d) {
    final day = dateOnly(d);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }

  /// Monday of the week [d] falls in.
  static DateTime weekStart(DateTime d) {
    final day = dateOnly(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }
}

/// Shop aisles used to group the shopping list.
enum ShoppingAisle {
  produce,
  meatFish,
  dairyEggs,
  bakery,
  pantry,
  drinks,
  other,
}

/// One line of the shopping list, summed across the week's plans.
class ShoppingItem {
  /// Stable identity used to remember the tick: the normalised name and
  /// unit.
  final String key;
  final String name;
  final double amount;
  final String unit;
  final ShoppingAisle aisle;

  /// Amount per person when plans from more than one person are merged.
  /// Keyed by owner id; a single-person list has one entry.
  final Map<String, double> perOwner;

  /// Added by hand rather than derived from a plan.
  final bool manual;

  const ShoppingItem({
    required this.key,
    required this.name,
    required this.amount,
    required this.unit,
    required this.aisle,
    this.perOwner = const {},
    this.manual = false,
  });
}

/// The ticks and hand-added lines of one week's shopping list.
class ShoppingListState {
  final Set<String> checked;

  /// key -> who ticked it and when, for a shared list.
  final Map<String, String> checkedBy;
  final List<ShoppingItem> manualItems;

  const ShoppingListState({
    this.checked = const {},
    this.checkedBy = const {},
    this.manualItems = const [],
  });

  ShoppingListState toggle(String key, {String? by}) {
    final next = {...checked};
    final nextBy = {...checkedBy};
    if (!next.remove(key)) {
      next.add(key);
      if (by != null) nextBy[key] = by;
    } else {
      nextBy.remove(key);
    }
    return ShoppingListState(
      checked: next,
      checkedBy: nextBy,
      manualItems: manualItems,
    );
  }

  ShoppingListState addManual(ShoppingItem item) => ShoppingListState(
    checked: checked,
    checkedBy: checkedBy,
    manualItems: [...manualItems, item],
  );

  ShoppingListState removeManual(String key) => ShoppingListState(
    checked: {...checked}..remove(key),
    checkedBy: {...checkedBy}..remove(key),
    manualItems: manualItems.where((i) => i.key != key).toList(),
  );

  Map<String, dynamic> toJson() => {
    'checked': checked.toList(),
    'checkedBy': checkedBy,
    'manual': [
      for (final i in manualItems)
        {
          'key': i.key,
          'name': i.name,
          'amount': i.amount,
          'unit': i.unit,
          'aisle': i.aisle.name,
        },
    ],
  };

  static ShoppingListState fromJson(Map<String, dynamic> json) {
    final checked = json['checked'];
    final checkedBy = json['checkedBy'];
    final manual = json['manual'];
    return ShoppingListState(
      checked: {
        if (checked is List)
          for (final k in checked)
            if (k is String) k,
      },
      checkedBy: {
        if (checkedBy is Map)
          for (final e in checkedBy.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      manualItems: [
        if (manual is List)
          for (final m in manual)
            if (m is Map && m['key'] is String && m['name'] is String)
              ShoppingItem(
                key: m['key'] as String,
                name: m['name'] as String,
                amount: (m['amount'] as num?)?.toDouble() ?? 0,
                unit: m['unit'] as String? ?? '',
                aisle: ShoppingAisle.values.firstWhere(
                  (a) => a.name == m['aisle'],
                  orElse: () => ShoppingAisle.other,
                ),
                manual: true,
              ),
      ],
    );
  }
}

/// Times of the planner reminders. Null means off.
class PlannerReminderSettings {
  /// Weekly: plan the week. [weekday] 1 = Monday.
  final ({int weekday, int hour, int minute})? planWeek;

  /// Weekly: do the shopping.
  final ({int weekday, int hour, int minute})? shopping;

  /// Daily: prepare tomorrow's planned food.
  final ({int hour, int minute})? prepare;

  /// Minutes after each meal's usual time to remind to log what was
  /// planned. Null means off.
  final int? logAfterMinutes;

  const PlannerReminderSettings({
    this.planWeek,
    this.shopping,
    this.prepare,
    this.logAfterMinutes,
  });

  static const off = PlannerReminderSettings();

  static const suggestedPlanWeek = (
    weekday: DateTime.sunday,
    hour: 18,
    minute: 0,
  );
  static const suggestedShopping = (
    weekday: DateTime.monday,
    hour: 19,
    minute: 30,
  );
  static const suggestedPrepare = (hour: 21, minute: 0);
  static const suggestedLogAfterMinutes = 30;

  Map<String, dynamic> toJson() => {
    if (planWeek != null)
      'planWeek': [planWeek!.weekday, planWeek!.hour, planWeek!.minute],
    if (shopping != null)
      'shopping': [shopping!.weekday, shopping!.hour, shopping!.minute],
    if (prepare != null) 'prepare': [prepare!.hour, prepare!.minute],
    if (logAfterMinutes != null) 'logAfterMinutes': logAfterMinutes,
  };

  static PlannerReminderSettings fromJson(Map<String, dynamic> json) {
    ({int weekday, int hour, int minute})? weekly(Object? raw) {
      if (raw is List && raw.length == 3 && raw.every((e) => e is int)) {
        return (
          weekday: (raw[0] as int).clamp(1, 7),
          hour: (raw[1] as int).clamp(0, 23),
          minute: (raw[2] as int).clamp(0, 59),
        );
      }
      return null;
    }

    final prepare = json['prepare'];
    final log = json['logAfterMinutes'];
    return PlannerReminderSettings(
      planWeek: weekly(json['planWeek']),
      shopping: weekly(json['shopping']),
      prepare:
          prepare is List &&
              prepare.length == 2 &&
              prepare.every((e) => e is int)
          ? (
              hour: (prepare[0] as int).clamp(0, 23),
              minute: (prepare[1] as int).clamp(0, 59),
            )
          : null,
      logAfterMinutes: log is int ? log.clamp(5, 240) : null,
    );
  }
}
