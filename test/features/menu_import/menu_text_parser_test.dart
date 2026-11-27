import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_amount_solver.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_text_parser.dart';

void main() {
  group('MenuTextParser text', () {
    test('days, meals and foods in Spanish', () {
      final menu = MenuTextParser.parse('''
Menú semana 1
LUNES
Desayuno: 60 g de avena, 250 ml leche
Media mañana
- plátano
- 20 gr almendras
Comida: arroz integral 150g + pechuga de pollo 120 g y ensalada
Merienda: yogur griego (1,25 pts)
Cena:
Salmón 130 g
Patata 200g
MARTES
Desayuno: 2 tostadas integrales, aceite 10 g
''');
      expect(menu.days, hasLength(2));
      final monday = menu.days.first;
      expect(monday.weekday, 1);
      expect(
        [for (final m in monday.meals) m.label],
        ['Desayuno', 'Media mañana', 'Comida', 'Merienda', 'Cena'],
      );
      final breakfast = monday.meals.first.foods;
      expect(breakfast.first.name, 'avena');
      expect(breakfast.first.amount, 60);
      expect(breakfast[1].unit, 'ml');
      final mid = monday.meals[1].foods;
      expect(mid.map((f) => f.name), ['plátano', 'almendras']);
      expect(mid[1].amount, 20);
      final lunch = monday.meals[2].foods;
      expect(lunch.map((f) => f.name), [
        'arroz integral',
        'pechuga de pollo',
        'ensalada',
      ]);
      expect(monday.meals[3].foods.single.points, 1.25);
      expect(menu.days[1].weekday, 2);
      expect(menu.days[1].meals.single.foods.first.count, 2);
    });

    test('English with numbered days and no meal names', () {
      final menu = MenuTextParser.parse('''
Day 1
Breakfast - oatmeal 50g, milk 200ml
Lunch: chicken breast 150 g, brown rice 180 g
Day 2
Dinner: salmon, potatoes
''');
      expect(menu.days.map((d) => d.index), [1, 2]);
      expect(menu.days.first.meals.first.label, 'Breakfast');
      expect(menu.days.first.meals.first.foods.first.amount, 50);
      expect(menu.days[1].meals.single.foods.map((f) => f.name), [
        'salmon',
        'potatoes',
      ]);
    });

    test('custom meal names of the user', () {
      final menu = MenuTextParser.parse(
        'Lunes\nPre-cama: kéfir 200 ml\nRecena: nueces 15 g',
        mealNames: ['Pre-cama'],
      );
      expect(menu.days.single.meals.map((m) => m.label), [
        'Pre-cama',
        'Recena',
      ]);
    });
  });

  group('MenuTextParser tables', () {
    test('week grid with days across (tab separated)', () {
      final menu = MenuTextParser.parse(
        '\tLunes\tMartes\tMiércoles\n'
        'Desayuno\tavena 50 g, leche\ttostadas, aceite\tyogur\n'
        'Comida\tlentejas 80 g\tpasta 90 g\tarroz 80 g, pollo 120 g\n'
        'Cena\ttortilla\tmerluza 150 g\tcrema de verduras\n',
      );
      expect(menu.days.map((d) => d.weekday), [1, 2, 3]);
      expect(menu.days.first.meals.map((m) => m.label), [
        'Desayuno',
        'Comida',
        'Cena',
      ]);
      expect(menu.days[2].meals[1].foods.map((f) => f.name), [
        'arroz',
        'pollo',
      ]);
    });

    test('markdown table with meals across', () {
      final menu = MenuTextParser.parse('''
| Day | Breakfast | Lunch | Dinner |
|-----|-----------|-------|--------|
| Monday | oats 50 g | chicken 150 g | salmon 130 g |
| Tuesday | toast | rice 150 g | eggs |
''');
      expect(menu.days.map((d) => d.weekday), [1, 2]);
      expect(menu.days.first.meals.map((m) => m.label), [
        'Breakfast',
        'Lunch',
        'Dinner',
      ]);
    });

    test('long table, one food per row', () {
      final menu = MenuTextParser.parse(
        'Día;Comida;Alimento;Cantidad\n'
        'Lunes;Desayuno;Avena;50 g\n'
        'Lunes;Desayuno;Leche;250 ml\n'
        'Lunes;Cena;Salmón;130 g\n'
        'Martes;Desayuno;Pan integral;60 g\n',
      );
      expect(menu.days, hasLength(2));
      expect(menu.days.first.meals.first.foods.map((f) => f.name), [
        'Avena',
        'Leche',
      ]);
      expect(menu.days.first.meals.first.foods[1].unit, 'ml');
      expect(menu.days[1].meals.single.foods.single.amount, 60);
    });
  });

  group('MenuAmountSolver', () {
    test('fills the meal budget with the free foods', () {
      // rice (mostly carbs), chicken (protein), oil (fat)
      const rice = MacroPoints(carbs: 1.04, protein: 0.11, fat: 0.09);
      const chicken = MacroPoints(carbs: 0, protein: 0.92, fat: 0.23);
      const oil = MacroPoints(carbs: 0, protein: 0, fat: 9);
      const budget = MacroPoints(carbs: 2.75, protein: 2.5, fat: 1);
      final grams = MenuAmountSolver.solve(
        per100: [rice, chicken, oil],
        budget: budget,
      );
      final got =
          rice * (grams[0] / 100) +
          chicken * (grams[1] / 100) +
          oil * (grams[2] / 100);
      expect((got.carbs - budget.carbs).abs(), lessThan(0.4));
      expect((got.protein - budget.protein).abs(), lessThan(0.4));
      expect((got.fat - budget.fat).abs(), lessThan(0.4));
      expect(grams.every((g) => g >= MenuAmountSolver.minGrams), isTrue);
    });

    test('no budget left gives the minimum amount', () {
      final grams = MenuAmountSolver.solve(
        per100: const [MacroPoints(carbs: 1, protein: 0, fat: 0)],
        budget: MacroPoints.zero,
      );
      expect(grams, [MenuAmountSolver.minGrams]);
    });
  });
}
