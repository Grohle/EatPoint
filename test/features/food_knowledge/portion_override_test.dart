import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/food_knowledge/data/portion_override_store.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';
import 'package:opennutritracker/features/food_knowledge/presentation/unit_weight_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../points/points_test_support.dart';

void main() {
  late PortionOverrideStore store;

  setUp(() {
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
    store = PortionOverrideStore(
      FakeHiveDBProvider(pointsSettingsBox: MemoryStringBox()),
    );
    FoodPortions.configure(user: store.portionFor);
  });

  tearDown(() => FoodPortions.configure());

  test(
    'the user\'s weight wins over the catalogue, and can be reset',
    () async {
      final before = PortionFormatter.forFood('Tortillas de trigo', 80);
      expect(before, isNotNull);

      await store.save(
        name: 'Tortillas de trigo',
        code: 'o:123',
        grams: 40,
        one: 'tortilla',
        other: 'tortillas',
        languageCode: 'es',
      );
      expect(
        PortionFormatter.forFood(
          'Tortillas de trigo',
          80,
          code: 'o:123',
        )!.label('es'),
        '2 tortillas',
      );
      // Found by name too, for the same food without its code.
      expect(PortionFormatter.forFood('tortillas de TRIGO', 120)!.count, 3);

      await store.reset('Tortillas de trigo', 'o:123');
      expect(store.hasOverride('Tortillas de trigo', 'o:123'), isFalse);
    },
  );

  test('the database can say a food has no unit at all', () {
    FoodPortions.configure(
      database: (code) => code == 'u:soup'
          ? (known: true, portion: null)
          : (known: false, portion: null),
    );
    expect(FoodPortions.of('Sopa de tomate', code: 'u:soup'), isNull);
    expect(FoodPortions.of('Huevo'), isNotNull);
  });

  testWidgets('the dialog saves a weight for the food', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showUnitWeightDialog(
                context,
                name: 'Pan de pita',
                store: store,
              ),
              child: const Text('open'),
            ),
          ),
        ),
        locale: const Locale('es'),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(bySemanticsId('unit-weight-grams'), '60');
    await tester.pump();
    final s = S.of(tester.element(find.byType(AlertDialog)));
    await tester.enterText(
      find.widgetWithText(TextField, s.unitWeightOne),
      'pan',
    );
    await tester.enterText(
      find.widgetWithText(TextField, s.unitWeightOther),
      'panes',
    );
    await tester.tap(bySemanticsId('unit-weight-save'));
    await tester.pumpAndSettle();
    expect(
      PortionFormatter.forFood('Pan de pita', 120)!.label('es'),
      '2 panes',
    );
  });
}
