import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diet_profile/data/diet_profile_store.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_profile_screen.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_warning.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../points/points_test_support.dart';

void main() {
  late DietProfileStore store;

  setUp(() async {
    await locator.reset();
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
    store = DietProfileStore(
      FakeHiveDBProvider(pointsSettingsBox: MemoryStringBox()),
    );
    locator.registerSingleton<DietProfileStore>(store);
  });

  tearDown(() => locator.reset());

  testWidgets('choices are saved as they change', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(const DietProfileScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vegetarian'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Halal'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Peanuts'));
    await tester.tap(find.text('Peanuts'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lactose'));
    await tester.tap(find.text('Lactose'));
    await tester.pumpAndSettle();
    final likes = find.descendant(
      of: bySemanticsId('diet-likes'),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(likes);
    await tester.enterText(likes, 'Salmón');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final saved = store.get();
    expect(saved.diet.name, 'vegetarian');
    expect(saved.religion, ReligiousDiet.halal);
    expect(saved.allergies, {Allergen.peanuts});
    expect(saved.intolerances, {Intolerance.lactose});
    expect(saved.likes, ['Salmón']);
  });

  testWidgets('the warning says why and what to choose instead', (
    tester,
  ) async {
    await store.save(
      const DietProfile(
        intolerances: {Intolerance.lactose},
        allergies: {Allergen.peanuts},
      ),
    );
    await tester.pumpWidget(
      localizedApp(
        const Column(
          children: [
            DietWarning('Whole milk'),
            DietWarning('Peanut butter'),
            DietWarning('Apple'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose the free-from version'), findsOneWidget);
    expect(find.textContaining('lactose-free versions'), findsOneWidget);
    expect(find.text("Doesn't fit your diet"), findsOneWidget);
    expect(find.textContaining('(allergy)'), findsOneWidget);
    expect(bySemanticsId('diet-warning'), findsNWidgets(2));
  });
}
