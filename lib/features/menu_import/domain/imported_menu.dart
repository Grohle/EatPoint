/// A menu read from text, a table or a photo, before it is matched to
/// foods and written into the planner.
library;

/// One food line of an imported meal, as written.
class ImportedFood {
  /// What to search for, e.g. "brown rice".
  final String name;

  /// Grams or ml when the source said so.
  final double? amount;

  /// 'g' or 'ml' when [amount] is set.
  final String? unit;

  /// Pieces when the source gave a count ("2 eggs").
  final double? count;

  /// Points when the source gave them ("rice 1.5 pts").
  final double? points;

  /// Energy and macros per 100 g, when the source (an AI reading) estimated
  /// them. Used only when no food in the databases matches.
  final ImportedNutrients? per100;

  const ImportedFood({
    required this.name,
    this.amount,
    this.unit,
    this.count,
    this.points,
    this.per100,
  });

  @override
  String toString() =>
      'ImportedFood($name, amount: $amount $unit, count: $count, '
      'points: $points)';
}

class ImportedNutrients {
  final double kcal;
  final double carbs;
  final double protein;
  final double fat;

  const ImportedNutrients({
    required this.kcal,
    required this.carbs,
    required this.protein,
    required this.fat,
  });
}

/// One meal of an imported day.
class ImportedMeal {
  /// The meal's label as written ("Desayuno", "Pre-workout"); null when the
  /// source gave none.
  final String? label;

  /// A dish name when the source named one ("Lentil stew").
  final String? dish;

  final List<ImportedFood> foods;

  const ImportedMeal({this.label, this.dish, this.foods = const []});

  ImportedMeal copyWith({String? label, List<ImportedFood>? foods}) =>
      ImportedMeal(
        label: label ?? this.label,
        dish: dish,
        foods: foods ?? this.foods,
      );
}

/// One day of an imported menu.
class ImportedDay {
  /// A calendar date, when the source gave one.
  final DateTime? date;

  /// 1 (Monday) to 7 (Sunday), when the source named the weekday.
  final int? weekday;

  /// 1-based position when the source numbered its days ("Day 3").
  final int? index;

  /// The day's heading as written.
  final String? label;

  final List<ImportedMeal> meals;

  const ImportedDay({
    this.date,
    this.weekday,
    this.index,
    this.label,
    this.meals = const [],
  });

  bool get isEmpty => meals.every((m) => m.foods.isEmpty);
}

class ImportedMenu {
  final List<ImportedDay> days;

  const ImportedMenu(this.days);

  bool get isEmpty => days.every((d) => d.isEmpty);

  int get foodCount => days.fold(
    0,
    (n, d) => n + d.meals.fold(0, (m, meal) => m + meal.foods.length),
  );
}
