import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_import_plan.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

/// One meal of another member's share of a joint menu.
class MemberMeal {
  final DateTime date;
  final String slotId;
  final List<PlannedItem> items;

  const MemberMeal({
    required this.date,
    required this.slotId,
    required this.items,
  });
}

/// Turns a menu generated for this user into another member's share of
/// it: the same dishes in their meals of the same kind (lunch with lunch,
/// dinner with dinner), with what their diet rules out swapped for
/// something of the same kind, and the amounts fitted to their points.
class MemberMenuAdapter {
  MemberMenuAdapter._();

  /// Labels each meal with its slot so the planner finds it exactly.
  static String _key(MealSlot slot) => 'eatpoint-slot:${slot.id}';

  static List<MemberMeal> adapt({
    required ImportedMenu menu,
    required Map<String, GenFood> foods,
    required List<MealSlot> mySlots,
    required String Function(MealSlot) myNameOf,
    required List<MealSlot> theirSlots,
    required Map<String, MacroPoints> theirBudgets,
    required List<GenFood> pool,
    required MenuCompanion them,
    required String languageCode,
    required DateTime start,
  }) {
    final known = <String, GenFood>{...foods};
    final days = <ImportedDay>[];
    for (final day in menu.days) {
      final meals = <ImportedMeal>[];
      for (final meal in day.meals) {
        final mine = meal.label == null
            ? null
            : MenuImportPlanner.slotForLabel(meal.label!, mySlots, myNameOf);
        if (mine == null) continue;
        final theirs = _matchingSlot(mine, mySlots, theirSlots);
        if (theirs == null) continue;
        final adapted = <ImportedFood>[];
        for (final food in meal.foods) {
          final swapped = _forThem(food, known, pool, them, languageCode);
          if (swapped != null) adapted.add(swapped);
        }
        if (adapted.isNotEmpty) {
          meals.add(
            ImportedMeal(label: _key(theirs), dish: meal.dish, foods: adapted),
          );
        }
      }
      days.add(
        ImportedDay(
          date: day.date,
          weekday: day.weekday,
          index: day.index,
          label: day.label,
          meals: meals,
        ),
      );
    }
    final plan = MenuImportPlanner.build(
      menu: ImportedMenu(days),
      slots: theirSlots,
      nameOf: _key,
      start: start,
      match: (f) => (meal: known[f.name]?.meal, usual: null),
      budgets: theirBudgets,
    );
    return [
      for (final day in plan)
        for (final meal in day.meals)
          MemberMeal(
            date: day.date,
            slotId: meal.slot.id,
            items: [
              for (final f in meal.foods)
                if (f.meal != null && f.grams > 0)
                  PlannedItem(
                    id: IdGenerator.getUniqueID(),
                    meal: f.meal!,
                    amount: f.grams,
                    unit: f.meal!.isLiquid ? 'ml' : 'g',
                  ),
            ],
          ),
    ];
  }

  /// Their meal for [mine]: the one of the same type in the same position
  /// (their second snack for my second snack).
  static MealSlot? _matchingSlot(
    MealSlot mine,
    List<MealSlot> mySlots,
    List<MealSlot> theirSlots,
  ) {
    final position = mySlots
        .where((s) => s.baseType == mine.baseType)
        .toList()
        .indexOf(mine);
    final same = theirSlots.where((s) => s.baseType == mine.baseType).toList();
    if (same.isEmpty) return null;
    return same[position.clamp(0, same.length - 1)];
  }

  /// [food] as they can have it: as it is, in its free-from version, or
  /// swapped for a food of the same kind. Null when nothing fits.
  static ImportedFood? _forThem(
    ImportedFood food,
    Map<String, GenFood> known,
    List<GenFood> pool,
    MenuCompanion them,
    String languageCode,
  ) {
    final gen = known[food.name];
    if (gen == null) return food;
    if (them.canEat(gen)) {
      final checker = them.checker;
      final name = checker == null
          ? gen.name
          : checker.adaptedName(
              gen.name,
              languageCode,
              conceptId: gen.conceptId,
            );
      if (name == gen.name) return food;
      final renamed = gen.renamed(name);
      known[name] = renamed;
      return _withName(food, name);
    }
    final swap = _swapFor(gen, pool, them, known);
    if (swap == null) return null;
    known[swap.name] = swap;
    // A protein's amount is fitted to their points; the rest keeps its
    // household amount.
    return ImportedFood(
      name: swap.name,
      amount: _isProtein(gen) ? null : food.amount,
      unit: _isProtein(gen) ? null : food.unit,
    );
  }

  static ImportedFood _withName(ImportedFood f, String name) => ImportedFood(
    name: name,
    amount: f.amount,
    unit: f.unit,
    count: f.count,
    points: f.points,
    per100: f.per100,
  );

  static bool _isProtein(GenFood f) =>
      ProteinKind.values.any((k) => MenuGenerator.isProteinKind(f, k));

  /// A food of the same kind as [gen] they can eat, preferring one already
  /// in the menu (fewer products to buy).
  static GenFood? _swapFor(
    GenFood gen,
    List<GenFood> pool,
    MenuCompanion them,
    Map<String, GenFood> inMenu,
  ) {
    bool Function(GenFood) sameKind;
    if (_isProtein(gen)) {
      sameKind = _isProtein;
    } else {
      const roles = ['fruit', 'veg', 'dairy', 'nuts', 'carb', 'fat', 'protein'];
      final role = roles.where(gen.has).firstOrNull;
      if (role == null) return null;
      sameKind = (f) => f.has(role);
    }
    final options = pool.where((f) => sameKind(f) && them.canEat(f)).toList();
    if (options.isEmpty) return null;
    final already = options.where((f) => inMenu.containsKey(f.name));
    return already.isNotEmpty ? already.first : options.first;
  }
}
