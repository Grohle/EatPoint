import 'package:flutter/widgets.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/data/meal_slot_assignments.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';

/// Logs a planned meal into the diary and takes it back out.
///
/// Logging remembers which diary entries it created (the entries of that
/// meal type on that day that weren't there before), so unlogging removes
/// exactly those and nothing the user logged by hand.
class PlannedMealLogger {
  final Future<List<IntakeEntity>> Function(IntakeTypeEntity, DateTime)
  _intakesOn;
  final Future<void> Function(IntakeEntity, DateTime) _delete;

  PlannedMealLogger({
    required Future<List<IntakeEntity>> Function(IntakeTypeEntity, DateTime)
    intakesOn,
    required Future<void> Function(IntakeEntity, DateTime) delete,
  }) : _intakesOn = intakesOn,
       _delete = delete;

  /// The app's logger: the intake repository and the diary's delete, which
  /// also takes the entry off the day's totals.
  factory PlannedMealLogger.app(BuildContext context) {
    final intakes = locator<IntakeRepository>();
    final diary = locator<CalendarDayBloc>();
    return PlannedMealLogger(
      intakesOn: (type, day) => intakes.getIntakeByDateAndType(type, day),
      delete: (intake, day) => diary.deleteIntakeItem(context, intake, day),
    );
  }

  /// Logs every item of [slot] on [day] with [add], and returns the day
  /// marked as logged with the entries it created.
  Future<DayPlan> log(
    DayPlan day,
    MealSlot slot,
    Future<void> Function(PlannedItem item) add,
  ) async {
    final items = day.itemsFor(slot.id);
    if (items.isEmpty) return day;
    final before = {
      for (final i in await _intakesOn(slot.baseType, day.date)) i.id,
    };
    await MealSlotContext.run(slot, () async {
      for (final item in items) {
        await add(item);
      }
    });
    final created = [
      for (final i in await _intakesOn(slot.baseType, day.date))
        if (!before.contains(i.id)) i.id,
    ];
    return day.withLogged(slot.id, true, intakeIds: created);
  }

  /// Removes what logging [slot] put in the diary and marks it as not
  /// logged. Meals logged before the entries were kept are matched by food
  /// and amount, one entry per planned item.
  Future<DayPlan> unlog(DayPlan day, MealSlot slot) async {
    final onDay = await _intakesOn(slot.baseType, day.date);
    final ids = day.loggedIntakes[slot.id];
    final toRemove = <IntakeEntity>[];
    if (ids != null && ids.isNotEmpty) {
      toRemove.addAll(onDay.where((i) => ids.contains(i.id)));
    } else {
      final pool = [...onDay];
      for (final item in day.itemsFor(slot.id)) {
        final match = pool.indexWhere((i) => _sameFood(i, item));
        if (match >= 0) toRemove.add(pool.removeAt(match));
      }
    }
    for (final intake in toRemove) {
      await _delete(intake, day.date);
    }
    return day.withLogged(slot.id, false);
  }

  static bool _sameFood(IntakeEntity intake, PlannedItem item) {
    final sameMeal =
        (intake.meal.code != null && intake.meal.code == item.meal.code) ||
        (intake.meal.name ?? '').trim().toLowerCase() ==
            item.name.trim().toLowerCase();
    return sameMeal &&
        intake.unit == item.unit &&
        (intake.amount - item.amount).abs() < 0.01;
  }

  /// Refreshes the screens that show the diary after a change.
  static void refreshDiary() {
    locator<HomeBloc>().add(const LoadItemsEvent());
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
  }

  /// Logs one planned item the way the amount sheet does.
  static Future<void> Function(PlannedItem) appAdd(
    BuildContext context,
    MealDetailBloc bloc,
    MealSlot slot,
    DateTime date,
  ) =>
      (item) => bloc.addIntake(
        context,
        item.unit,
        item.amount.toString(),
        slot.baseType,
        item.meal,
        date,
      );
}
