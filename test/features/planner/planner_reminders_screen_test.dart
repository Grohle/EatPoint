import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/data/planner_reminder_service.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/presentation/planner_reminders_screen.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

import '../../helpers/fake_hive_db_provider.dart';
import 'planner_test_support.dart';

class _FakeNotifications extends Fake implements NotificationService {
  bool grant = true;
  int requests = 0;

  @override
  Future<bool> requestPermission() async {
    requests++;
    return grant;
  }
}

class _FakeReminderService extends Fake implements PlannerReminderService {
  final calls = <PlannerReminderSettings>[];
  int upcomingLength = 0;

  @override
  Future<void> reschedule({
    required PlannerReminderSettings settings,
    required List<DayPlan> upcoming,
    required PlannerReminderTexts texts,
    List<MealSlot>? slots,
    DateTime? now,
  }) async {
    calls.add(settings);
    upcomingLength = upcoming.length;
  }
}

void main() {
  late PlannerDataSource source;
  late _FakeNotifications notifications;
  late _FakeReminderService reminders;

  setUp(() {
    source = PlannerDataSource(
      FakeHiveDBProvider(pointsSettingsBox: MemoryStringBox()),
    );
    notifications = _FakeNotifications();
    reminders = _FakeReminderService();
    locator.registerSingleton<PlannerDataSource>(source);
    locator.registerSingleton<NotificationService>(notifications);
    locator.registerSingleton<PlannerReminderService>(reminders);
  });

  tearDown(() async => locator.reset());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(const PlannerRemindersScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('everything is off at first and the note is shown', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('All reminders are off'), findsOneWidget);
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches, hasLength(4));
    expect(switches.every((s) => !s.value), isTrue);
  });

  testWidgets('turning one on saves the suggestion and reschedules', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(
      source.getReminders().planWeek,
      PlannerReminderSettings.suggestedPlanWeek,
    );
    expect(notifications.requests, 1);
    expect(reminders.calls.single.planWeek, isNotNull);
    expect(reminders.upcomingLength, 7);
    expect(find.text('Sunday · 6:00 PM'), findsOneWidget);
  });

  testWidgets('turning the last one off does not ask for permission', (
    tester,
  ) async {
    await source.saveReminders(
      const PlannerReminderSettings(prepare: (hour: 21, minute: 0)),
    );
    await pump(tester);
    await tester.tap(find.byType(Switch).at(2));
    await tester.pumpAndSettle();
    expect(notifications.requests, 0);
    expect(source.getReminders().prepare, isNull);
    expect(reminders.calls.single.prepare, isNull);
  });

  testWidgets('a refused permission keeps the setting and shows a snackbar', (
    tester,
  ) async {
    notifications.grant = false;
    await pump(tester);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(source.getReminders().shopping, isNotNull);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(reminders.calls, hasLength(1));
  });

  testWidgets('the log reminder offers 15, 30 and 60 minutes', (tester) async {
    await source.saveReminders(
      const PlannerReminderSettings(logAfterMinutes: 30),
    );
    await pump(tester);
    expect(find.text('30 min after each meal'), findsOneWidget);
    await tester.tap(find.text('Log what you planned'));
    await tester.pumpAndSettle();
    expect(find.text('15 min after each meal'), findsOneWidget);
    expect(find.text('60 min after each meal'), findsOneWidget);
    await tester.tap(find.text('60 min after each meal'));
    await tester.pumpAndSettle();
    expect(source.getReminders().logAfterMinutes, 60);
  });

  testWidgets('tapping the body of an enabled weekly reminder picks a '
      'weekday', (tester) async {
    await source.saveReminders(
      const PlannerReminderSettings(
        planWeek: PlannerReminderSettings.suggestedPlanWeek,
      ),
    );
    await pump(tester);
    await tester.tap(find.text('Plan the week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunday').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friday').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(source.getReminders().planWeek?.weekday, DateTime.friday);
    expect(source.getReminders().planWeek?.hour, 18);
  });
}
