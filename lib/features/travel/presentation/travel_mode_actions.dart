import 'package:flutter/widgets.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/data/planner_reminder_service.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/presentation/planner_reminders_screen.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/sync/domain/household_auto_sync.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/features/travel/domain/travel_mode.dart';

/// Turns travel mode on and off and applies what that pauses or resumes.
class TravelModeActions {
  TravelModeActions._();

  static TravelModeStore get _store => locator<TravelModeStore>();

  /// Saves [mode] and brings reminders and sync in line with it.
  static Future<void> apply(BuildContext context, TravelMode mode) async {
    final before = _store.current();
    final texts = plannerReminderTextsOf(context);
    await _store.save(mode);
    await _sideEffects(before, _store.current(), texts);
  }

  static Future<void> setEnabled(BuildContext context, bool enabled) async {
    final before = _store.current();
    final texts = plannerReminderTextsOf(context);
    await _store.setEnabled(enabled);
    await _sideEffects(before, _store.current(), texts);
  }

  /// Ends a trip whose last day has passed. Call where the app comes back
  /// to (the home screen).
  static Future<void> endIfExpired(BuildContext context) async {
    if (!locator.isRegistered<TravelModeStore>()) return;
    final before = _store.get();
    if (!before.hasExpiredAt(DateTime.now())) return;
    final texts = plannerReminderTextsOf(context);
    if (await _store.endIfExpired()) {
      await _sideEffects(
        before.copyWith(enabled: true),
        _store.current(),
        texts,
      );
    }
  }

  static Future<void> _sideEffects(
    TravelMode before,
    TravelMode after,
    PlannerReminderTexts texts,
  ) async {
    final pausedBefore = before.enabled && before.pauseReminders;
    final pausedAfter = after.enabled && after.pauseReminders;
    if (locator.isRegistered<PlannerReminderService>() &&
        locator.isRegistered<PlannerDataSource>()) {
      final service = locator<PlannerReminderService>();
      if (pausedAfter && !pausedBefore) {
        await service.cancelAll();
      } else if (!pausedAfter && pausedBefore) {
        final planner = locator<PlannerDataSource>();
        final today = DayPlan.dateOnly(DateTime.now());
        final slots = locator.isRegistered<PointsSettingsDataSource>()
            ? (await locator<PointsSettingsDataSource>().getSettings())
                  .effectiveMealSlots
            : null;
        await service.reschedule(
          settings: planner.getReminders(),
          upcoming: [
            for (var i = 0; i < 7; i++)
              planner.getDay(DateTime(today.year, today.month, today.day + i)),
          ],
          texts: texts,
          slots: slots,
        );
      }
    }
    if (before.enabled && before.pauseHouseholdSync && !after.enabled) {
      HouseholdAutoSync.instance.syncSoon(Duration.zero);
    }
  }
}
