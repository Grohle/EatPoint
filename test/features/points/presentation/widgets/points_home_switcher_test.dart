import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';
import 'package:opennutritracker/features/points/presentation/widgets/points_home_switcher.dart';

import '../../points_test_support.dart';

void main() {
  late PointsSettingsDataSource source;

  setUp(() => source = registerPointsLocator());

  tearDown(() async => locator.reset());

  Future<void> pump(WidgetTester tester, {Locale? locale}) async {
    await tester.pumpWidget(
      localizedApp(
        const Scaffold(
          body: SingleChildScrollView(
            child: PointsHomeSwitcher(
              caloriesView: Text('CALORIES VIEW'),
              intakes: {},
              kcalSupplied: 500,
              kcalGoal: 2000,
            ),
          ),
        ),
        locale: locale ?? const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('points mode shows the day card and the switch button', (
    tester,
  ) async {
    await source.saveSettings(
      PointsSettings.defaults.copyWith(budgetGuideAcknowledged: true),
    );
    await pump(tester);

    expect(find.text("Today's points"), findsOneWidget);
    expect(bySemanticsId('home-switch-to-calories'), findsOneWidget);
    expect(find.text('Calorie view'), findsOneWidget);
    expect(find.text('CALORIES VIEW'), findsNothing);
    // 10 + 7.5 + 5.25 rounds to 22.75 pts with nothing logged.
    expect(find.text('22.75'), findsOneWidget);
    expect(find.text('pts left'), findsOneWidget);
  });

  testWidgets('switching to calories saves the setting and swaps the view', (
    tester,
  ) async {
    await source.saveSettings(
      PointsSettings.defaults.copyWith(budgetGuideAcknowledged: true),
    );
    await pump(tester);

    await tester.tap(bySemanticsId('home-switch-to-calories'));
    await tester.pumpAndSettle();

    expect((await source.getSettings()).pointsModeEnabled, false);
    expect(find.text('CALORIES VIEW'), findsOneWidget);
    expect(find.text('Points view'), findsOneWidget);
    expect(find.text("Today's points"), findsNothing);

    await tester.tap(bySemanticsId('home-switch-to-points'));
    await tester.pumpAndSettle();
    expect((await source.getSettings()).pointsModeEnabled, true);
    expect(find.text("Today's points"), findsOneWidget);
  });

  testWidgets('calorie view stays when points mode is saved off', (
    tester,
  ) async {
    await source.saveSettings(
      PointsSettings.defaults.copyWith(pointsModeEnabled: false),
    );
    await pump(tester);
    expect(find.text('CALORIES VIEW'), findsOneWidget);
    expect(find.text('Points view'), findsOneWidget);
    // No guide while points mode is off.
    expect(find.text('Your suggested points'), findsNothing);
  });

  testWidgets('the guide sheet opens once and "Start with this" saves', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Your suggested points'), findsOneWidget);
    expect(find.textContaining('This budget is a guide only'), findsOneWidget);
    expect(
      find.textContaining('not medical or dietetic advice'),
      findsOneWidget,
    );
    expect((await source.getSettings()).budgetGuideAcknowledged, false);

    await tester.tap(bySemanticsId('points-guide-accept'));
    await tester.pumpAndSettle();

    expect(find.text('Your suggested points'), findsNothing);
    expect((await source.getSettings()).budgetGuideAcknowledged, true);
    // The save bumps the revision and reloads; the guide must not return.
    expect(find.text('Your suggested points'), findsNothing);
  });

  testWidgets('the guide does not reopen after a reload', (tester) async {
    await pump(tester);
    expect(find.text('Your suggested points'), findsOneWidget);

    // Dismiss without acknowledging, then trigger a reload.
    Navigator.of(tester.element(find.text('Your suggested points'))).pop();
    await tester.pumpAndSettle();
    await source.saveSettings(await source.getSettings());
    await tester.pumpAndSettle();

    expect(find.text('Your suggested points'), findsNothing);
  });

  testWidgets('Spanish uses decimal commas', (tester) async {
    await source.saveSettings(
      PointsSettings.defaults.copyWith(budgetGuideAcknowledged: true),
    );
    await pump(tester, locale: const Locale('es'));
    expect(find.text('22,75'), findsOneWidget);
    expect(find.textContaining('22.75'), findsNothing);
  });
}
