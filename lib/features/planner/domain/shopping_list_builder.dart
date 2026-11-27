import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';

/// A recipe's ingredients for a given amount of the finished dish, so the
/// list shows what to buy rather than the dish.
typedef RecipeIngredients =
    List<({MealEntity meal, double grams})>? Function(
      MealEntity recipeMeal,
      double dishGrams,
    );

/// Builds a shopping list from day plans.
class ShoppingListBuilder {
  /// [plans] pairs each day plan with the id of the person it belongs to,
  /// so a shared household gets one list with each person's share.
  static List<ShoppingItem> build(
    Iterable<({String owner, DayPlan plan})> plans, {
    RecipeIngredients? recipeIngredients,
  }) {
    final totals = <String, _Acc>{};

    void add(String owner, MealEntity meal, double amount, String unit) {
      final name = (meal.name ?? '').trim();
      if (name.isEmpty || amount <= 0) return;
      final key = '${normalise(name)}|$unit';
      final acc = totals.putIfAbsent(
        key,
        () => _Acc(name, unit, aisleFor(name)),
      );
      acc.amount += amount;
      acc.perOwner[owner] = (acc.perOwner[owner] ?? 0) + amount;
    }

    for (final (:owner, :plan) in plans) {
      for (final items in plan.meals.values) {
        for (final item in items) {
          final ingredients = item.meal.source == MealSourceEntity.recipe
              ? recipeIngredients?.call(item.meal, item.amount)
              : null;
          if (ingredients != null && ingredients.isNotEmpty) {
            for (final i in ingredients) {
              add(owner, i.meal, i.grams, i.meal.isLiquid ? 'ml' : 'g');
            }
          } else {
            add(owner, item.meal, item.amount, item.unit);
          }
        }
      }
    }

    final items = [
      for (final e in totals.entries)
        ShoppingItem(
          key: e.key,
          name: e.value.name,
          amount: e.value.amount,
          unit: e.value.unit,
          aisle: e.value.aisle,
          perOwner: e.value.perOwner,
        ),
    ];
    items.sort((a, b) {
      final byAisle = a.aisle.index.compareTo(b.aisle.index);
      return byAisle != 0
          ? byAisle
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  /// Lower-case, accents removed, single spaces.
  static String normalise(String name) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    final lower = name.toLowerCase().trim();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      final i = from.indexOf(ch);
      buffer.write(i >= 0 ? to[i] : ch);
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  static final Map<ShoppingAisle, List<String>> _keywords = {
    ShoppingAisle.meatFish: [
      'pollo',
      'pavo',
      'ternera',
      'cerdo',
      'cordero',
      'carne',
      'jamon',
      'lomo',
      'salmon',
      'atun',
      'merluza',
      'bacalao',
      'pescado',
      'gamba',
      'langostino',
      'mejillon',
      'sardina',
      'chicken',
      'turkey',
      'beef',
      'pork',
      'lamb',
      'meat',
      'ham',
      'salmon',
      'tuna',
      'cod',
      'fish',
      'shrimp',
      'prawn',
      'burger',
      'hamburguesa',
      'seitan',
      'tofu',
      'tempeh',
      'heura',
    ],
    ShoppingAisle.dairyEggs: [
      'leche',
      'yogur',
      'queso',
      'huevo',
      'clara',
      'nata',
      'mantequilla',
      'kefir',
      'skyr',
      'milk',
      'yogurt',
      'yoghurt',
      'cheese',
      'egg',
      'cream',
      'butter',
      'bebida de',
      'drink',
      'cottage',
    ],
    ShoppingAisle.bakery: [
      'pan',
      'tostada',
      'tortilla integral',
      'wrap',
      'bread',
      'toast',
      'bagel',
      'brioche',
    ],
    ShoppingAisle.produce: [
      'verdura',
      'hortaliza',
      'lechuga',
      'tomate',
      'cebolla',
      'pimiento',
      'zanahoria',
      'calabacin',
      'brocoli',
      'espinaca',
      'patata',
      'boniato',
      'seta',
      'champinon',
      'aguacate',
      'platano',
      'manzana',
      'pera',
      'naranja',
      'mandarina',
      'fresa',
      'kiwi',
      'uva',
      'melon',
      'sandia',
      'fruta',
      'limon',
      'vegetable',
      'lettuce',
      'tomato',
      'onion',
      'pepper',
      'carrot',
      'potato',
      'mushroom',
      'avocado',
      'banana',
      'apple',
      'pear',
      'orange',
      'berry',
      'fruit',
      'lemon',
      'spinach',
      'broccoli',
      'salad',
      'ensalada',
    ],
    ShoppingAisle.drinks: [
      'agua',
      'zumo',
      'cafe',
      'te ',
      'cerveza',
      'refresco',
      'water',
      'juice',
      'coffee',
      'tea',
      'beer',
      'soda',
    ],
    ShoppingAisle.pantry: [
      'arroz',
      'pasta',
      'avena',
      'harina',
      'cereal',
      'legumbre',
      'garbanzo',
      'lenteja',
      'alubia',
      'aceite',
      'frutos secos',
      'almendra',
      'nuez',
      'cacahuete',
      'crema de',
      'semilla',
      'quinoa',
      'cuscus',
      'azucar',
      'miel',
      'tomate frito',
      'salsa',
      'proteina en polvo',
      'rice',
      'oat',
      'flour',
      'bean',
      'lentil',
      'chickpea',
      'oil',
      'nut',
      'almond',
      'peanut',
      'seed',
      'sugar',
      'honey',
      'sauce',
      'protein powder',
      'whey',
      'conserva',
      'lata',
    ],
  };

  /// A best guess at the aisle from the food's name, in Spanish or English.
  static ShoppingAisle aisleFor(String name) {
    final n = normalise(name);
    // Specific phrases first: "tomate frito" is pantry, not produce.
    for (final aisle in [
      ShoppingAisle.pantry,
      ShoppingAisle.dairyEggs,
      ShoppingAisle.meatFish,
      ShoppingAisle.bakery,
      ShoppingAisle.drinks,
      ShoppingAisle.produce,
    ]) {
      for (final keyword in _keywords[aisle]!) {
        if (keyword.contains(' ') && n.contains(keyword)) return aisle;
      }
    }
    for (final aisle in [
      ShoppingAisle.meatFish,
      ShoppingAisle.dairyEggs,
      ShoppingAisle.bakery,
      ShoppingAisle.produce,
      ShoppingAisle.drinks,
      ShoppingAisle.pantry,
    ]) {
      for (final keyword in _keywords[aisle]!) {
        if (!keyword.contains(' ') &&
            RegExp('(^|[^a-z])$keyword').hasMatch(n)) {
          return aisle;
        }
      }
    }
    return ShoppingAisle.other;
  }

  /// Plain-text list for sharing, grouped by aisle with ticks.
  static String toText(
    List<ShoppingItem> items,
    Set<String> checked, {
    required String Function(ShoppingAisle) aisleName,
    required String Function(ShoppingItem) amountText,
  }) {
    final buffer = StringBuffer();
    ShoppingAisle? current;
    for (final item in items) {
      if (item.aisle != current) {
        if (current != null) buffer.writeln();
        current = item.aisle;
        buffer.writeln(aisleName(item.aisle).toUpperCase());
      }
      final tick = checked.contains(item.key) ? '☑' : '☐';
      buffer.writeln('$tick ${item.name} — ${amountText(item)}');
    }
    return buffer.toString().trimRight();
  }

  /// CSV with a header row: aisle, item, amount, unit, done.
  static String toCsv(
    List<ShoppingItem> items,
    Set<String> checked, {
    required String Function(ShoppingAisle) aisleName,
    required List<String> header,
  }) {
    String cell(String v) =>
        v.contains(RegExp(r'[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    final lines = [header.map(cell).join(',')];
    for (final i in items) {
      lines.add(
        [
          aisleName(i.aisle),
          i.name,
          i.amount.round().toString(),
          i.unit,
          checked.contains(i.key) ? '1' : '0',
        ].map(cell).join(','),
      );
    }
    return lines.join('\n');
  }
}

class _Acc {
  final String name;
  final String unit;
  final ShoppingAisle aisle;
  double amount = 0;
  final Map<String, double> perOwner = {};

  _Acc(this.name, this.unit, this.aisle);
}
