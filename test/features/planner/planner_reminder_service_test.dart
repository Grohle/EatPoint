import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/planner/data/planner_reminder_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location madrid;

  setUpAll(() {
    tz_data.initializeTimeZones();
    madrid = tz.getLocation('Europe/Madrid');
  });

  tz.TZDateTime at(int y, int m, int d, int h, int min) =>
      tz.TZDateTime(madrid, y, m, d, h, min);

  group('PlannerReminderService.nextWeekly', () {
    test('later the same day', () {
      // 2026-11-23 is a Monday.
      final next = PlannerReminderService.nextWeekly(
        at(2026, 11, 23, 8, 0),
        DateTime.monday,
        19,
        30,
      );
      expect(next, at(2026, 11, 23, 19, 30));
    });

    test('same weekday and time already passed goes a week ahead', () {
      final next = PlannerReminderService.nextWeekly(
        at(2026, 11, 23, 20, 0),
        DateTime.monday,
        19,
        30,
      );
      expect(next, at(2026, 11, 30, 19, 30));
    });

    test('exactly now is not "after now"', () {
      final next = PlannerReminderService.nextWeekly(
        at(2026, 11, 23, 19, 30),
        DateTime.monday,
        19,
        30,
      );
      expect(next, at(2026, 11, 30, 19, 30));
    });

    test('a weekday earlier in the week wraps to next week', () {
      // Wednesday asking for Monday.
      final next = PlannerReminderService.nextWeekly(
        at(2026, 11, 25, 10, 0),
        DateTime.monday,
        9,
        0,
      );
      expect(next, at(2026, 11, 30, 9, 0));
      expect(next.weekday, DateTime.monday);
    });

    test('a weekday later in the week', () {
      final next = PlannerReminderService.nextWeekly(
        at(2026, 11, 25, 10, 0),
        DateTime.sunday,
        18,
        0,
      );
      expect(next, at(2026, 11, 29, 18, 0));
    });

    test(
      'keeps wall-clock time across the end of daylight saving time',
      () {
        // Spain moves back on 2026-10-25; Saturday 24th -> Monday 26th.
        final next = PlannerReminderService.nextWeekly(
          at(2026, 10, 24, 12, 0),
          DateTime.monday,
          19,
          30,
        );
        expect(next.weekday, DateTime.monday);
        expect(next.hour, 19);
        expect(next.minute, 30);
      },
    );
  });
}
