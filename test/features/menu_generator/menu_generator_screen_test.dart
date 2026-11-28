import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diet_profile/data/diet_profile_store.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/menu_generator/data/menu_generator_sources.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/features/menu_generator/presentation/menu_generator_screen.dart';
import 'package:opennutritracker/features/menu_import/presentation/menu_import_review_screen.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_menu.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../points/points_test_support.dart';

class _KeyedBox extends MemoryStringBox {
  @override
  Iterable<dynamic> get keys => data.keys;
}

class _NoSecrets extends Fake implements FlutterSecureStorage {}

void main() {
  setUp(() async {
    await locator.reset();
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
    final box = MemoryStringBox();
    registerPointsLocator(box: box);
    final db = FakeHiveDBProvider(pointsSettingsBox: box);
    locator.registerSingleton<PlannerDataSource>(PlannerDataSource(db));
    final store = DietProfileStore(db);
    await store.save(
      const DietProfile(
        intolerances: {Intolerance.lactose},
        allergies: {Allergen.peanuts},
        likes: ['salmón'],
      ),
    );
    locator.registerSingleton<DietProfileStore>(store);
  });

  tearDown(() => locator.reset());

  testWidgets('shows the diet and generates a menu to review', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(MenuGeneratorScreen(initialDay: DateTime(2026, 11, 30))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Allergies: peanuts'), findsOneWidget);
    expect(find.textContaining('Likes: salmón'), findsOneWidget);
    expect(bySemanticsId('generator-efficient'), findsOneWidget);
    // Without an AI provider only the phone engine can be chosen.
    await tester.scrollUntilVisible(
      find.textContaining('Set up an AI provider'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Set up an AI provider'), findsOneWidget);

    await tester.tap(find.text('3 days'));
    await tester.pumpAndSettle();
    final generate = bySemanticsId('generator-generate');
    await tester.scrollUntilVisible(
      generate,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(generate);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MenuImportReviewScreen), findsOneWidget);
  });

  testWidgets('a joint menu gives the other member their share', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final household = HouseholdStore(
      FakeHiveDBProvider(pointsSettingsBox: _KeyedBox()),
      _NoSecrets(),
    );
    await household.saveHousehold(
      const Household(
        householdId: '0123456789abcdef0123456789abcdef',
        memberId: 'aaaaaaaaaaaaaaaa',
        memberName: 'Ann',
        backend: SyncBackendConfig(
          kind: SyncBackendKind.webdav,
          url: 'https://example.org/dav',
        ),
      ),
    );
    await household.saveMember(
      MemberSnapshot(
        memberId: 'bbbbbbbbbbbbbbbb',
        name: 'Bo',
        updatedAt: DateTime(2026, 11, 30),
        profile: MemberProfile(
          slots: [
            for (final slot in MealSlot.builtIn())
              MemberSlot(id: slot.id, baseType: slot.baseType),
          ],
          budgets: {
            for (final slot in MealSlot.builtIn())
              slot.id: const MacroPoints(carbs: 4, protein: 3, fat: 2),
          },
          diet: const DietProfile(diet: DietStyle.vegetarian),
        ),
      ),
    );
    locator.registerSingleton<HouseholdStore>(household);

    await tester.pumpWidget(
      localizedApp(MenuGeneratorScreen(initialDay: DateTime(2026, 11, 30))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 day'));
    final bo = bySemanticsId('generator-with-bbbbbbbbbbbbbbbb');
    await tester.scrollUntilVisible(
      bo,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(bo);
    await tester.pumpAndSettle();
    final generate = bySemanticsId('generator-generate');
    await tester.scrollUntilVisible(
      generate,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(generate);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    final save = bySemanticsId('menu-import-save');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(save);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    final edits = household.pendingEdits();
    expect(edits, hasLength(4), reason: 'one per meal of the day');
    expect(edits.every((e) => e.memberId == 'bbbbbbbbbbbbbbbb'), isTrue);
    final vegetarian = MenuCompanion(diet: DietStyle.vegetarian);
    for (final edit in edits) {
      for (final item in edit.items) {
        expect(
          vegetarian.canEat(
            GenFood.of(item.meal, knowledge: FoodKnowledge.instance!),
          ),
          isTrue,
          reason: item.name,
        );
      }
    }
  });

  Future<HouseholdStore> householdWith(List<MemberSnapshot> members) async {
    final household = HouseholdStore(
      FakeHiveDBProvider(pointsSettingsBox: _KeyedBox()),
      _NoSecrets(),
    );
    await household.saveHousehold(
      const Household(
        householdId: '0123456789abcdef0123456789abcdef',
        memberId: 'aaaaaaaaaaaaaaaa',
        memberName: 'Ann',
        backend: SyncBackendConfig(
          kind: SyncBackendKind.webdav,
          url: 'https://example.org/dav',
        ),
      ),
    );
    for (final m in members) {
      await household.saveMember(m);
    }
    locator.registerSingleton<HouseholdStore>(household);
    return household;
  }

  MemberProfile profile({bool allowEdits = true}) => MemberProfile(
    allowEdits: allowEdits,
    slots: [
      for (final slot in MealSlot.builtIn())
        MemberSlot(id: slot.id, baseType: slot.baseType),
    ],
    budgets: {
      for (final slot in MealSlot.builtIn())
        slot.id: const MacroPoints(carbs: 4, protein: 3, fat: 2),
    },
  );

  testWidgets('everyone in the household shows, with why some can\'t be chosen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await householdWith([
      MemberSnapshot(
        memberId: 'bbbbbbbbbbbbbbbb',
        name: 'Bo',
        updatedAt: DateTime(2026, 11, 30),
      ),
      MemberSnapshot(
        memberId: 'cccccccccccccccc',
        name: 'Cy',
        updatedAt: DateTime(2026, 11, 30),
        profile: profile(allowEdits: false),
      ),
    ]);
    await tester.pumpWidget(
      localizedApp(MenuGeneratorScreen(initialDay: DateTime(2026, 11, 30))),
    );
    await tester.pumpAndSettle();
    final s = S.of(tester.element(find.byType(MenuGeneratorScreen)));
    await tester.scrollUntilVisible(
      find.text(s.generatorMemberNoEdits('Cy')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(s.generatorMemberNoProfile('Bo')), findsOneWidget);
    expect(find.text(s.generatorMemberNoEdits('Cy')), findsOneWidget);
    final chip = tester.widget<FilterChip>(
      find.descendant(
        of: bySemanticsId('generator-with-bbbbbbbbbbbbbbbb'),
        matching: find.byType(FilterChip),
      ),
    );
    expect(chip.onSelected, isNull);
  });

  testWidgets('a menu can be made only for another member', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final household = await householdWith([
      MemberSnapshot(
        memberId: 'bbbbbbbbbbbbbbbb',
        name: 'Bo',
        updatedAt: DateTime(2026, 11, 30),
        profile: profile(),
      ),
    ]);
    int? popped;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped = await Navigator.of(context).push(
              MaterialPageRoute<int>(
                builder: (_) =>
                    MenuGeneratorScreen(initialDay: DateTime(2026, 11, 30)),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 day'));
    Future<void> tapId(String id) async {
      final f = bySemanticsId(id);
      await tester.scrollUntilVisible(
        f,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    await tapId('generator-with-bbbbbbbbbbbbbbbb');
    await tapId('generator-for-me');
    await tapId('generator-generate');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    // Straight to Bo, nothing into this user's menu.
    expect(find.byType(MenuImportReviewScreen), findsNothing);
    expect(popped, 1);
    expect(household.pendingEdits(), hasLength(4));
  });

  test('the AI brief carries the meals, points and diet', () {
    final slots = MealSlot.builtIn();
    final brief = MenuGeneratorBrief.build(
      days: [DateTime(2026, 11, 30), DateTime(2026, 12, 1)],
      slots: slots,
      nameOf: (s) => s.baseType.name,
      budgets: {
        for (final s in slots)
          s.id: const MacroPoints(carbs: 2, protein: 1.5, fat: 1),
      },
      profile: const DietProfile(
        diet: DietStyle.vegetarian,
        religion: ReligiousDiet.hindu,
        allergies: {Allergen.sesame},
        intolerances: {Intolerance.lactose},
        dislikes: ['coliflor'],
        likes: ['lentejas'],
      ),
      languageCode: 'es',
    );
    expect(brief, contains('2026-11-30, 2026-12-01'));
    expect(brief, contains('Spanish'));
    expect(brief, contains('"lunch"'));
    expect(brief, contains('protein 1.5'));
    expect(brief, contains('vegetarian'));
    expect(brief, contains('no beef'));
    expect(brief, contains('ALLERGIES'));
    expect(brief, contains('sesame'));
    expect(brief, contains('lactose-free'));
    expect(brief, contains('Never use: coliflor'));
    expect(brief, contains('likes: lentejas'));
  });
}
