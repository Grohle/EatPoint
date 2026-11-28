import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/presentation/planner_calendar_screen.dart';
import 'package:opennutritracker/features/planner/presentation/planner_screen.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_menu.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/fake_hive_db_provider.dart';
import 'planner_test_support.dart';
import '../points/points_test_support.dart' show registerPointsLocator;

class _KeyedBox extends MemoryStringBox {
  @override
  Iterable<dynamic> get keys => data.keys;
}

class _NoSecrets extends Fake implements FlutterSecureStorage {}

const _bo = 'bbbbbbbbbbbbbbbb';

void main() {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  late PlannerDataSource planner;
  late HouseholdStore household;

  Future<void> saveBo({bool allowEdits = true}) => household.saveMember(
    MemberSnapshot(
      memberId: _bo,
      name: 'Bo',
      updatedAt: day,
      profile: MemberProfile(allowEdits: allowEdits),
      days: [
        dayPlan(day, {
          IntakeTypeEntity.lunch: [plannedItem('Lentejas', 300)],
        }),
      ],
    ),
  );

  setUp(() async {
    await locator.reset();
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
    final box = _KeyedBox();
    registerPointsLocator(box: box);
    final db = FakeHiveDBProvider(pointsSettingsBox: box);
    planner = PlannerDataSource(db);
    locator.registerSingleton<PlannerDataSource>(planner);
    locator.registerSingleton<TravelModeStore>(TravelModeStore(db));
    household = HouseholdStore(db, _NoSecrets());
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
    locator.registerSingleton<HouseholdStore>(household);
    await planner.saveDay(
      dayPlan(day, {
        IntakeTypeEntity.lunch: [plannedItem('Arroz', 80)],
        IntakeTypeEntity.dinner: [plannedItem('Salmón', 150)],
      }),
    );
  });

  tearDown(() => locator.reset());

  Future<S> open(WidgetTester tester, {PlannerScreen? screen}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localizedApp(screen ?? PlannerScreen(initialDay: day)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    return S.of(tester.element(find.byType(PlannerScreen)));
  }

  Future<void> swipeLeft(WidgetTester tester, Finder target) async {
    await tester.drag(target, const Offset(-500, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('the circle switches to a member\'s menu, which edits go to', (
    tester,
  ) async {
    await saveBo();
    final s = await open(tester);
    expect(find.text('Arroz'), findsOneWidget);

    await tester.tap(bySemanticsId('planner-viewing'));
    await tester.pumpAndSettle();
    await tester.tap(bySemanticsId('planner-view-$_bo'));
    await tester.pumpAndSettle();

    expect(find.text(s.householdMemberMenu('Bo')), findsOneWidget);
    expect(find.text('Lentejas'), findsOneWidget);
    expect(find.text('Arroz'), findsNothing);
    // Only the user's own diary is logged from here.
    expect(bySemanticsId('planner-log-lunch'), findsNothing);

    await tester.tap(bySemanticsId('planner-delete-lunch'));
    await tester.pumpAndSettle();
    final edits = household.pendingEdits();
    expect(edits, hasLength(1));
    expect(edits.single.memberId, _bo);
    expect(edits.single.slotId, 'lunch');
    expect(edits.single.items, isEmpty);
    // The user's own menu is untouched.
    expect(planner.getDay(day).itemsFor('lunch'), hasLength(1));

    // Back to the user's own menu.
    await tester.tap(bySemanticsId('planner-viewing'));
    await tester.pumpAndSettle();
    await tester.tap(bySemanticsId('planner-view-me'));
    await tester.pumpAndSettle();
    expect(find.text('Arroz'), findsOneWidget);
  });

  testWidgets('a member who allows no changes is shown read-only', (
    tester,
  ) async {
    await saveBo(allowEdits: false);
    final s = await open(
      tester,
      screen: PlannerScreen(initialDay: day, initialMember: _bo),
    );
    expect(find.text('Lentejas'), findsOneWidget);
    expect(find.text(s.householdMemberNoEdits('Bo')), findsOneWidget);
    expect(bySemanticsId('planner-delete-lunch'), findsNothing);
    expect(bySemanticsId('planner-edit-lunch'), findsNothing);
    expect(bySemanticsId('planner-add-lunch'), findsNothing);
  });

  testWidgets('a member\'s food can be copied to the user\'s menu', (
    tester,
  ) async {
    await saveBo();
    final s = await open(
      tester,
      screen: PlannerScreen(initialDay: day, initialMember: _bo),
    );
    await tester.tap(find.byTooltip(s.plannerCopyToMine));
    await tester.pumpAndSettle();
    expect(
      planner.getDay(day).itemsFor('lunch').map((i) => i.name),
      containsAll(['Arroz', 'Lentejas']),
    );
  });

  testWidgets('swiping a meal left deletes it after asking', (tester) async {
    final s = await open(tester);
    // From the meal's header: the rows below swipe away one food.
    await swipeLeft(
      tester,
      find.descendant(
        of: find.byKey(ValueKey('planner-meal-$day-lunch')),
        matching: find.text('Lunch'),
      ),
    );
    expect(find.text(s.plannerConfirmDeleteMeal('Lunch')), findsOneWidget);
    await tester.tap(find.text(s.plannerDeleteDay).last);
    await tester.pumpAndSettle();
    expect(planner.getDay(day).itemsFor('lunch'), isEmpty);
    expect(planner.getDay(day).itemsFor('dinner'), hasLength(1));
  });

  testWidgets('swiping a food left removes it after asking', (tester) async {
    final s = await open(tester);
    await swipeLeft(tester, find.text('Salmón'));
    expect(find.text(s.plannerRemoveItemTitle('Salmón')), findsOneWidget);
    await tester.tap(find.text(s.plannerRemoveItem).last);
    await tester.pumpAndSettle();
    expect(planner.getDay(day).itemsFor('dinner'), isEmpty);
    expect(find.text('Salmón'), findsNothing);
    expect(planner.getDay(day).itemsFor('lunch'), hasLength(1));
  });

  group('calendar', () {
    Future<S> openCalendar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        localizedApp(PlannerCalendarScreen(initialDay: day)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      return S.of(tester.element(find.byType(PlannerCalendarScreen)));
    }

    Finder cell(DateTime date) =>
        bySemanticsId('planner-calendar-${DayPlan.dateKey(date)}');

    testWidgets('a day slides up everyone\'s meals; one swipes away', (
      tester,
    ) async {
      await saveBo();
      final s = await openCalendar(tester);
      await tester.tap(cell(day));
      await tester.pumpAndSettle();
      expect(find.text(s.householdMemberMenu('Bo')), findsOneWidget);
      expect(find.text('Arroz'), findsOneWidget);
      expect(find.text('Lentejas'), findsOneWidget);

      await swipeLeft(
        tester,
        bySemanticsId('calendar-meal-$_bo-${DayPlan.dateKey(day)}-lunch'),
      );
      await tester.tap(find.text(s.plannerDeleteDay).last);
      await tester.pumpAndSettle();
      expect(household.pendingEdits().single.memberId, _bo);
      expect(find.text('Lentejas'), findsNothing);
      // The user's own meals stay.
      expect(planner.getDay(day).itemsFor('lunch'), hasLength(1));
    });

    testWidgets('a meal tapped there opens in its owner\'s weekly menu', (
      tester,
    ) async {
      await saveBo();
      final s = await open(tester);
      await tester.tap(bySemanticsId('planner-calendar'));
      await tester.pumpAndSettle();
      await tester.tap(cell(day));
      await tester.pumpAndSettle();
      await tester.tap(
        bySemanticsId('calendar-meal-$_bo-${DayPlan.dateKey(day)}-lunch'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlannerCalendarScreen), findsNothing);
      expect(find.text(s.householdMemberMenu('Bo')), findsOneWidget);
      expect(find.text('Lentejas'), findsOneWidget);
      // The meal is pointed out for a moment.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a long press chooses days, whose menus can be deleted', (
      tester,
    ) async {
      final next = DateTime(day.year, day.month, day.day + 1);
      // Days of the month on screen only.
      final other = next.month == day.month
          ? next
          : DateTime(day.year, day.month, day.day - 1);
      await planner.saveDay(
        dayPlan(other, {
          IntakeTypeEntity.breakfast: [plannedItem('Avena', 50)],
        }),
      );
      final s = await openCalendar(tester);
      await tester.longPress(cell(day));
      await tester.pumpAndSettle();
      await tester.tap(cell(other));
      await tester.pumpAndSettle();
      expect(find.text(s.calendarSelectedDays('2')), findsOneWidget);

      await tester.tap(bySemanticsId('calendar-delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.plannerDeleteDay).last);
      await tester.pumpAndSettle();
      expect(planner.getDay(day).isEmpty, isTrue);
      expect(planner.getDay(other).isEmpty, isTrue);
      expect(find.text(s.calendarSelectedDays('2')), findsNothing);

      await tester.tap(find.text(s.plannerUndo));
      await tester.pumpAndSettle();
      expect(planner.getDay(day).isEmpty, isFalse);
      expect(planner.getDay(other).isEmpty, isFalse);
    });

    testWidgets('chosen days become a trip', (tester) async {
      final s = await openCalendar(tester);
      await tester.longPress(cell(day));
      await tester.pumpAndSettle();
      await tester.tap(bySemanticsId('calendar-travel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final mode = locator<TravelModeStore>().get();
      expect(mode.enabled, isTrue);
      expect(mode.from, day);
      expect(mode.until, day);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(s.calendarTravel, isNotEmpty);
    });
  });
}
