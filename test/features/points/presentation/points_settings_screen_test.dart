import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';
import 'package:opennutritracker/features/points/presentation/points_settings_screen.dart';

import '../points_test_support.dart';

void main() {
  late PointsSettingsDataSource source;

  setUp(() => source = registerPointsLocator());

  tearDown(() async => locator.reset());

  Future<void> pump(WidgetTester tester) async {
    // Tall viewport so the whole ListView is built.
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(const PointsSettingsScreen()));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String id) =>
      tester.widget<TextField>(fieldWithId(id)).controller!.text;

  testWidgets('loads and shows the suggestion line and the methods', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Points'), findsOneWidget); // app bar title
    expect(
      find.text('22.75 pts · Carbs 10 · Protein 7.5 · Fat 5.25'),
      findsOneWidget,
    );
    expect(find.text('About 2000 kcal a day'), findsOneWidget);
    expect(find.text('Lean mass, protein first'), findsOneWidget);
    expect(find.text('Calorie goal and macros'), findsOneWidget);
    expect(
      tester
          .widget<RadioListTile<PointsBudgetMethod>>(
            find.byType(RadioListTile<PointsBudgetMethod>).first,
          )
          .value,
      PointsBudgetMethod.leanMass,
    );
    // Lean-mass fields are visible; own-budget fields are not.
    expect(fieldWithId('points-protein-per-kg'), findsOneWidget);
    expect(text(tester, 'points-protein-per-kg'), '1.5');
    expect(text(tester, 'points-carb-share'), '65');
    expect(fieldWithId('points-own-carbs'), findsNothing);
  });

  testWidgets('switching to app macros and saving persists the method', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Calorie goal and macros'));
    await tester.pumpAndSettle();

    // The suggestion follows the draft and the lean-mass fields go away.
    expect(find.text('22 pts · Carbs 12 · Protein 6 · Fat 4'), findsOneWidget);
    expect(fieldWithId('points-protein-per-kg'), findsNothing);

    await tester.tap(bySemanticsId('points-settings-save'));
    await tester.pumpAndSettle();

    final saved = await source.getSettings();
    expect(saved.budgetMethod, PointsBudgetMethod.appMacros);
    // The screen pops itself after saving.
    expect(find.byType(PointsSettingsScreen), findsNothing);
  });

  testWidgets('own daily points shows three fields prefilled from the guide', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Set my own daily points'));
    await tester.pumpAndSettle();

    expect(text(tester, 'points-own-carbs'), '10');
    expect(text(tester, 'points-own-protein'), '7.5');
    expect(text(tester, 'points-own-fat'), '5.25');

    await tester.enterText(fieldWithId('points-own-carbs'), '11,6');
    await tester.pump();
    await tester.tap(bySemanticsId('points-settings-save'));
    await tester.pumpAndSettle();

    final own = (await source.getSettings()).dailyBudgetOverride!;
    // Typed values snap to quarter points.
    expect(own.carbs, 11.5);
    expect(own.protein, 7.5);
    expect(own.fat, 5.25);
  });

  testWidgets('turning own points off clears the override', (tester) async {
    await source.saveSettings(
      PointsSettings.defaults.copyWith(
        dailyBudgetOverride: () =>
            const MacroPoints(carbs: 8, protein: 6, fat: 4),
      ),
    );
    await pump(tester);
    expect(text(tester, 'points-own-carbs'), '8');

    await tester.tap(find.text('Set my own daily points'));
    await tester.pumpAndSettle();
    expect(fieldWithId('points-own-carbs'), findsNothing);

    await tester.tap(bySemanticsId('points-settings-save'));
    await tester.pumpAndSettle();
    expect((await source.getSettings()).dailyBudgetOverride, isNull);
  });
}
