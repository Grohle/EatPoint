import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';

void main() {
  final knowledge = FoodKnowledge.parse(
    File(FoodKnowledge.assetPath).readAsStringSync(),
  );

  group('match', () {
    final cases = {
      'Pechuga de pollo a la plancha': 'chicken_breast',
      'Chicken breast': 'chicken_breast',
      'Aguacate': 'avocado',
      'Huevos camperos': 'egg',
      'Atún en lata al natural': 'tuna_can',
      'Aceite de oliva virgen extra': 'olive_oil',
      'Leche semidesnatada': 'milk',
      'Copos de avena': 'oats',
      'Salmón': 'salmon',
      'Pan integral': 'bread_slice',
      'Plátano de Canarias': 'banana',
      'Tomates cherry': 'cherry_tomato',
      'Pechuga de pavo': 'turkey_breast',
      'Almendras tostadas': 'almonds',
      'Yogur griego natural': 'yogurt',
      'Merluza': 'white_fish',
    };
    cases.forEach((name, id) {
      test('$name → $id', () => expect(knowledge.match(name)?.id, id));
    });

    test('unknown foods and partial words do not match', () {
      expect(knowledge.match('Quinoa'), isNull);
      // "pan" inside "panceta" is not bread.
      expect(knowledge.match('Panceta'), isNull);
      expect(knowledge.match(''), isNull);
    });
  });

  group('PortionFormatter', () {
    FoodPortion main(String id) =>
        knowledge.concepts.firstWhere((c) => c.id == id).mainPortion!;

    test('halves for big units, in both languages', () {
      final fillet = main('chicken_breast'); // 136 g
      final a = PortionFormatter.describe(204, fillet)!;
      expect(a.count, 1.5);
      expect(a.label('es'), '1½ filetes');
      expect(a.label('en'), '1½ fillets');
      final avocado = PortionFormatter.describe(100, main('avocado'))!;
      expect(avocado.label('es'), '½ aguacate');
      expect(avocado.label('en'), '½ avocado');
      expect(PortionFormatter.describe(50, main('egg'))!.label('es'), '1 huevo');
      expect(
        PortionFormatter.describe(100, main('egg'))!.label('en'),
        '2 eggs',
      );
    });

    test('whole numbers for small units', () {
      final cherry = main('cherry_tomato'); // 17 g
      final a = PortionFormatter.describe(85, cherry)!;
      expect(a.count, 5);
      expect(a.label('es'), '5 tomates cherry');
    });

    test('nothing when no round count is close', () {
      final fillet = main('chicken_breast');
      expect(PortionFormatter.describe(20, fillet), isNull);
      expect(PortionFormatter.describe(5000, fillet), isNull);
      expect(PortionFormatter.describe(0, fillet), isNull);
    });

    test('count text', () {
      expect(PortionAmount.countText(0.5), '½');
      expect(PortionAmount.countText(1), '1');
      expect(PortionAmount.countText(2.5), '2½');
    });
  });

  test('every portion has a positive weight and names in both languages', () {
    expect(knowledge.concepts.length, greaterThan(80));
    for (final c in knowledge.concepts) {
      for (final p in c.portions) {
        expect(p.grams, greaterThan(0), reason: c.id);
        expect(p.es.one, isNotEmpty);
        expect(p.en.other, isNotEmpty);
      }
    }
  });
}
