import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/food_db/domain/food_database.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';

void main() {
  setUpAll(
    () => FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    ),
  );
  tearDown(() => FoodPortions.configure());

  String? units(String name, double grams) =>
      PortionFormatter.forFood(name, grams)?.label('es');

  test('real names get the right unit and weight', () {
    // A wheat tortilla weighs 35-45 g: 70 g is about two, never eight.
    expect(units('Tortillas de trigo', 80), '2 tortillas');
    expect(units('Wrap integral', 40), '1 tortilla');
    // Not every "tortilla" is a wrap.
    expect(units('Tortilla de patatas', 150), '1 ración');
    expect(units('Tortitas de maíz', 27), '3 tortitas');
    expect(units('Pechuga de pavo en lonchas', 50), '5 lonchas');
    expect(units('Pechuga de pavo', 120), '1 filete');
    expect(units('Pan de pita', 60), '1 pan de pita');
    expect(units('Salchichas Frankfurt', 90), '2 salchichas');
    expect(units('Hamburguesa de ternera', 240), '2 hamburguesas');
    expect(units('Pan de hamburguesa', 60), '1 pan');
  });

  test('prepared forms of a fruit or vegetable have no unit', () {
    expect(FoodKnowledge.instance!.match('Zumo de naranja'), isNull);
    expect(FoodKnowledge.instance!.match('Tomate frito'), isNull);
    expect(FoodKnowledge.instance!.match('Patatas fritas onduladas'), isNull);
    expect(FoodKnowledge.instance!.match('Naranja')!.id, 'orange');
  });

  test('a database food\'s own unit wins over the catalogue', () {
    final db = FoodDatabase.parse('''{
      "format": "eatpoint-foods", "version": 2, "foods": [
        {"i": "o:1", "s": "off", "es": "Tortillas mexicanas", "k": 300,
         "c": 50, "p": 8, "f": 7,
         "u": {"g": 38, "es": ["tortilla", "tortillas"], "en": ["tortilla", "tortillas"]}},
        {"i": "o:2", "s": "off", "es": "Zumo de manzana", "k": 45,
         "c": 11, "p": 0, "f": 0, "u": 0}
      ]}''');
    FoodPortions.configure(
      database: (code) =>
          db.byCode(code)?.unit ?? (known: false, portion: null),
    );
    final tortillas = db.foods.first.toMealEntity('es');
    expect(
      PortionFormatter.forFood(
        tortillas.name!,
        76,
        code: tortillas.code,
      )!.label('es'),
      '2 tortillas',
    );
    final juice = db.foods.last.toMealEntity('es');
    expect(FoodPortions.of(juice.name!, code: juice.code), isNull);
  });

  test('the shipped database has its own units', () {
    final file = File('data/food_db/eatpoint-foods-v2.json.gz');
    final db = FoodDatabase.parseGzip(file.readAsBytesSync());
    final withUnit = db.foods.where((f) => f.unit.known).length;
    expect(withUnit, greaterThan(2000));
  });
}
