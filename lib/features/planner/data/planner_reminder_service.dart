import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:timezone/timezone.dart' as tz;

/// Localised texts for the planner notifications, resolved by the caller
/// (notifications are scheduled from a screen, where the locale is known).
class PlannerReminderTexts {
  final String channelName;
  final String channelDescription;
  final String planWeekTitle;
  final String planWeekBody;
  final String shoppingTitle;
  final String shoppingBody;
  final String prepareTitle;
  final String Function(String dishes) prepareBody;
  final String logTitle;
  final String logBody;
  final String Function(MealSlot meal) mealName;

  const PlannerReminderTexts({
    required this.channelName,
    required this.channelDescription,
    required this.planWeekTitle,
    required this.planWeekBody,
    required this.shoppingTitle,
    required this.shoppingBody,
    required this.prepareTitle,
    required this.prepareBody,
    required this.logTitle,
    required this.logBody,
    required this.mealName,
  });
}

/// Schedules the planner's local notifications. Ids 100–199 are reserved
/// for it so they never collide with the app's own reminders.
class PlannerReminderService {
  static const _channelId = 'planner_reminders';
  static const _planWeekId = 100;
  static const _shoppingId = 101;
  static const _prepareBase = 110; // + day offset 0..6
  static const _logBase = 120; // + day * 11 + meal index, up to 196
  static const _maxMealsPerDay = 11;
  static const _lastId = 199;

  /// When each built-in meal is usually eaten, for the "log what you
  /// planned" nudge.
  static const mealTimes = {
    IntakeTypeEntity.breakfast: (hour: 9, minute: 0),
    IntakeTypeEntity.lunch: (hour: 14, minute: 30),
    IntakeTypeEntity.snack: (hour: 18, minute: 0),
    IntakeTypeEntity.dinner: (hour: 21, minute: 30),
  };

  final _log = Logger('PlannerReminderService');
  final NotificationService _notifications;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  PlannerReminderService(this._notifications);

  /// Cancels every planner notification (travel mode pauses them).
  Future<void> cancelAll() async {
    try {
      await _notifications.initialize();
      for (var id = _planWeekId; id <= _lastId; id++) {
        await _plugin.cancel(id: id);
      }
    } catch (e) {
      _log.warning('Could not cancel planner reminders: $e');
    }
  }

  /// Cancels every planner notification and schedules the ones [settings]
  /// asks for. [upcoming] are the plans for today and the next six days.
  Future<void> reschedule({
    required PlannerReminderSettings settings,
    required List<DayPlan> upcoming,
    required PlannerReminderTexts texts,
    List<MealSlot>? slots,
    DateTime? now,
  }) async {
    final meals = (slots == null || slots.isEmpty ? MealSlot.builtIn() : slots)
        .take(_maxMealsPerDay)
        .toList();
    final times = timesFor(meals);
    try {
      await _notifications.initialize();
      for (var id = _planWeekId; id <= _lastId; id++) {
        await _plugin.cancel(id: id);
      }
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          texts.channelName,
          channelDescription: texts.channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      );
      final current = tz.TZDateTime.from(now ?? DateTime.now(), tz.local);

      final planWeek = settings.planWeek;
      if (planWeek != null) {
        await _plugin.zonedSchedule(
          id: _planWeekId,
          title: texts.planWeekTitle,
          body: texts.planWeekBody,
          scheduledDate: nextWeekly(
            current,
            planWeek.weekday,
            planWeek.hour,
            planWeek.minute,
          ),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
      final shopping = settings.shopping;
      if (shopping != null) {
        await _plugin.zonedSchedule(
          id: _shoppingId,
          title: texts.shoppingTitle,
          body: texts.shoppingBody,
          scheduledDate: nextWeekly(
            current,
            shopping.weekday,
            shopping.hour,
            shopping.minute,
          ),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }

      final prepare = settings.prepare;
      final logAfter = settings.logAfterMinutes;
      for (var day = 0; day < upcoming.length && day < 7; day++) {
        final plan = upcoming[day];
        // The evening before this plan's day.
        if (prepare != null && !plan.isEmpty) {
          final at = tz.TZDateTime(
            tz.local,
            plan.date.year,
            plan.date.month,
            plan.date.day - 1,
            prepare.hour,
            prepare.minute,
          );
          if (at.isAfter(current)) {
            final dishes = [
              for (final items in plan.meals.values)
                for (final item in items) item.name,
            ].where((n) => n.isNotEmpty).toSet().take(4).join(', ');
            await _plugin.zonedSchedule(
              id: _prepareBase + day,
              title: texts.prepareTitle,
              body: texts.prepareBody(dishes),
              scheduledDate: at,
              notificationDetails: details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
          }
        }
        if (logAfter != null) {
          for (var m = 0; m < meals.length; m++) {
            final meal = meals[m];
            if (plan.itemsFor(meal.id).isEmpty ||
                plan.logged.contains(meal.id)) {
              continue;
            }
            final time = times[m];
            final at = tz.TZDateTime(
              tz.local,
              plan.date.year,
              plan.date.month,
              plan.date.day,
              time.hour,
              time.minute,
            ).add(Duration(minutes: logAfter));
            if (!at.isAfter(current)) continue;
            await _plugin.zonedSchedule(
              id: _logBase + day * _maxMealsPerDay + m,
              title: '${texts.logTitle} · ${texts.mealName(meal)}',
              body: texts.logBody,
              scheduledDate: at,
              notificationDetails: details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
          }
        }
      }
    } catch (e) {
      // A reminder that cannot be scheduled must never break the planner.
      _log.warning('Could not schedule planner reminders: $e');
    }
  }

  /// When each of [meals] is usually eaten: a built-in meal at its usual
  /// time, a meal the user added spread evenly between the meals around it
  /// (from 07:00 before the first to 23:00 after the last).
  static List<({int hour, int minute})> timesFor(List<MealSlot> meals) {
    final known = <int?>[
      for (final meal in meals)
        meal.isBuiltIn
            ? mealTimes[meal.baseType]!.hour * 60 +
                  mealTimes[meal.baseType]!.minute
            : null,
    ];
    final minutes = <int>[];
    for (var i = 0; i < meals.length; i++) {
      final k = known[i];
      if (k != null) {
        minutes.add(k);
        continue;
      }
      var before = i - 1;
      while (before >= 0 && known[before] == null) {
        before--;
      }
      var after = i + 1;
      while (after < meals.length && known[after] == null) {
        after++;
      }
      final from = before >= 0 ? known[before]! : 7 * 60;
      final to = after < meals.length ? known[after]! : 23 * 60;
      final steps = after - before;
      final at = from + ((to - from) * (i - before) / steps).round();
      minutes.add(at.clamp(0, 23 * 60 + 59));
    }
    return [for (final m in minutes) (hour: m ~/ 60, minute: m % 60)];
  }

  /// The next [weekday] (1 = Monday) at [hour]:[minute] strictly after
  /// [now].
  static tz.TZDateTime nextWeekly(
    tz.TZDateTime now,
    int weekday,
    int hour,
    int minute,
  ) {
    // Calendar days, not elapsed time: adding a Duration across a DST
    // change would shift the wall-clock time by an hour.
    tz.TZDateTime at(int dayOffset) => tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day + dayOffset,
      hour,
      minute,
    );
    final days = (weekday - now.weekday) % 7;
    final candidate = at(days);
    return candidate.isAfter(now) ? candidate : at(days + 7);
  }
}
