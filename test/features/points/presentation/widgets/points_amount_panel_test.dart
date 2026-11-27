import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/points/presentation/widgets/points_amount_panel.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../points_test_support.dart';

class _FakeMealDetailBloc extends Fake implements MealDetailBloc {
  final _controller = StreamController<MealDetailState>.broadcast();
  MealDetailState _state;

  _FakeMealDetailBloc(double kcal)
    : _state = MealDetailInitial(
        totalQuantityConverted: '190',
        selectedUnit: 'g',
        totalKcal: kcal,
      );

  void emitKcal(double kcal) {
    _state = MealDetailInitial(
      totalQuantityConverted: '100',
      selectedUnit: 'g',
      totalKcal: kcal,
    );
    _controller.add(_state);
  }

  @override
  MealDetailState get state => _state;

  @override
  Stream<MealDetailState> get stream => _controller.stream;

  @override
  Future<void> close() => _controller.close();
}

void main() {
  late TextEditingController quantity;
  late List<(String?, String?)> changes;
  late _FakeMealDetailBloc bloc;

  setUp(() {
    registerPointsLocator(
      mealUsed: const MacroPoints(carbs: 1, protein: 0.5, fat: 0.25),
    );
    quantity = TextEditingController(text: '190');
    changes = [];
    bloc = _FakeMealDetailBloc(0);
  });

  tearDown(() async {
    quantity.dispose();
    await bloc.close();
    await locator.reset();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool expanded = true,
    Locale locale = const Locale('en'),
    bool liquid = false,
    double kcal = 253.33,
  }) async {
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: SingleChildScrollView(
            child: PointsAmountPanel(
              product: pointsTestMeal(liquid: liquid),
              day: DateTime(2026, 1, 1),
              intakeType: IntakeTypeEntity.lunch,
              mealDetailBloc: bloc,
              quantityController: quantity,
              onQuantityOrUnitChanged: (q, u) => changes.add((q, u)),
              expanded: expanded,
            ),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
    // The kcal arrive after the first frame on purpose: with a non-zero
    // total in initState the panel reads Localizations too early (see the
    // skipped test below).
    if (kcal > 0) {
      bloc.emitKcal(kcal);
      await tester.pumpAndSettle();
    }
  }

  String pointsFieldText(WidgetTester tester) =>
      tester.widget<TextField>(fieldWithId('points-field')).controller!.text;

  testWidgets('shows the points for the current amount (en)', (tester) async {
    await pump(tester);
    expect(pointsFieldText(tester), '2.53');
    expect(find.text('1.33 pts / 100 g'), findsOneWidget);
    expect(find.text('1 pt = 75 g'), findsOneWidget);
    expect(find.text('2.5 pts'), findsOneWidget);
  });

  testWidgets('shows decimal commas in Spanish', (tester) async {
    await pump(tester, locale: const Locale('es'));
    expect(pointsFieldText(tester), '2,53');
    expect(find.textContaining('1,33'), findsWidgets);
    expect(find.textContaining('1.33'), findsNothing);
  });

  testWidgets('quick chip writes rounded grams and shows the exact hint', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('Exact:'), findsNothing);

    await tester.tap(bySemanticsId('points-quick-2-5'));
    await tester.pumpAndSettle();

    expect(quantity.text, '190');
    expect(changes.last, ('190', 'g'));
    expect(pointsFieldText(tester), '2.5');
    // 2.5 pts is 187.5 g exactly; 190 g is what gets weighed.
    expect(find.textContaining('Exact: 187.5'), findsOneWidget);
    expect(find.textContaining('weigh 190 g'), findsOneWidget);
  });

  testWidgets('uses ml for liquids', (tester) async {
    await pump(tester, liquid: true);
    await tester.tap(bySemanticsId('points-quick-2-5'));
    await tester.pumpAndSettle();
    expect(changes.last, ('190', 'ml'));
  });

  testWidgets('plus and minus step by a quarter point', (tester) async {
    await pump(tester);
    await tester.tap(bySemanticsId('points-step-up'));
    await tester.pumpAndSettle();
    expect(pointsFieldText(tester), '2.75');

    await tester.tap(bySemanticsId('points-step-down'));
    await tester.pumpAndSettle();
    await tester.tap(bySemanticsId('points-step-down'));
    await tester.pumpAndSettle();
    expect(pointsFieldText(tester), '2.25');
    expect(changes.length, 3);
  });

  testWidgets('minus stops at zero and clears the amount', (tester) async {
    await pump(tester, kcal: 0);
    await tester.tap(bySemanticsId('points-step-down'));
    await tester.pumpAndSettle();
    expect(pointsFieldText(tester), '');
    expect(quantity.text, '');
    expect(changes.last.$1, '');
  });

  testWidgets('typing points accepts a comma and updates the grams', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(fieldWithId('points-field'), '1,5');
    await tester.pump();
    // 1.5 pts / 1.3333 per 100 g = 112.5 g, rounded to something weighable.
    expect(changes, isNotEmpty);
    expect(changes.last.$2, 'g');
    expect(quantity.text, changes.last.$1);
    expect(double.parse(quantity.text), closeTo(112.5, 5));
  });

  testWidgets('follows the bloc when the grams change', (tester) async {
    await pump(tester);
    bloc.emitKcal(100);
    await tester.pumpAndSettle();
    expect(pointsFieldText(tester), '1');
  });

  testWidgets('collapsed shows only the one-line summary', (tester) async {
    await pump(tester, expanded: false);
    expect(find.text('2.53 pts · 1.33 pts / 100'), findsOneWidget);
    expect(bySemanticsId('points-field'), findsNothing);
    expect(bySemanticsId('points-step-up'), findsNothing);
    expect(find.byType(MealFitStrip), findsNothing);
  });

  testWidgets('shows the meal-fit strip with the meal budget', (tester) async {
    await pump(tester);
    expect(find.byType(MealFitStrip), findsOneWidget);
    expect(find.text('Lunch: how this fits'), findsOneWidget);
  });

  testWidgets(
    'opening with a non-zero amount does not read Localizations in initState',
    (tester) async {
      bloc = _FakeMealDetailBloc(253.33);
      await pump(tester, kcal: 0);
      expect(tester.takeException(), isNull);
      expect(pointsFieldText(tester), '2.53');
    },
  );

  testWidgets('renders nothing for a food without energy', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: PointsAmountPanel(
            product: pointsTestMeal(noEnergy: true),
            day: DateTime(2026, 1, 1),
            intakeType: IntakeTypeEntity.lunch,
            mealDetailBloc: bloc,
            quantityController: quantity,
            onQuantityOrUnitChanged: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(bySemanticsId('points-field'), findsNothing);
  });

  group('MealFitStrip', () {
    Future<void> pumpStrip(
      WidgetTester tester, {
      required MacroPoints budget,
      required MacroPoints used,
      required MacroPoints serving,
    }) async {
      await tester.pumpWidget(
        localizedApp(
          Scaffold(
            body: MealFitStrip(
              mealName: 'Dinner',
              budget: budget,
              used: used,
              serving: serving,
            ),
          ),
        ),
      );
    }

    Color? colourOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text).first).style?.color;

    testWidgets('renders title, three rows and totals', (tester) async {
      await pumpStrip(
        tester,
        budget: const MacroPoints(carbs: 3, protein: 2, fat: 1),
        used: const MacroPoints(carbs: 1, protein: 0.5, fat: 0.25),
        serving: const MacroPoints(carbs: 1, protein: 0.5, fat: 0.25),
      );
      final s = lookupS(const Locale('en'));
      expect(find.text('Dinner: how this fits'), findsOneWidget);
      expect(find.text(s.pointsCarbsLabel), findsOneWidget);
      expect(find.text(s.pointsProteinLabel), findsOneWidget);
      expect(find.text(s.pointsFatLabel), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('0.5 / 1'), findsOneWidget);
    });

    testWidgets('shows a "1 / 1" total at exactly the budget, not over', (
      tester,
    ) async {
      await pumpStrip(
        tester,
        budget: const MacroPoints(carbs: 1, protein: 1, fat: 1),
        used: const MacroPoints(carbs: 0.5, protein: 0.5, fat: 0.5),
        serving: const MacroPoints(carbs: 0.5, protein: 0.5, fat: 0.5),
      );
      expect(find.text('1 / 1'), findsNWidgets(3));
      final error = Theme.of(
        tester.element(find.byType(MealFitStrip)),
      ).colorScheme.error;
      expect(colourOf(tester, '1 / 1') == error, isFalse);
    });

    testWidgets('a total over budget uses the error colour', (tester) async {
      await pumpStrip(
        tester,
        budget: const MacroPoints(carbs: 1, protein: 2, fat: 2),
        used: const MacroPoints(carbs: 0.75, protein: 0, fat: 0),
        serving: const MacroPoints(carbs: 0.5, protein: 0, fat: 0),
      );
      final error = Theme.of(
        tester.element(find.byType(MealFitStrip)),
      ).colorScheme.error;
      expect(find.text('1.25 / 1'), findsOneWidget);
      expect(colourOf(tester, '1.25 / 1'), error);
      // The under-budget rows keep the default colour.
      expect(colourOf(tester, '0 / 2'), isNot(error));
    });
  });
}
