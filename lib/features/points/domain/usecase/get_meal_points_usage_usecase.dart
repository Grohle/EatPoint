import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/points/data/meal_slot_assignments.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';

/// The points already logged in one meal on one day.
class GetMealPointsUsageUsecase {
  final GetIntakeUsecase _getIntakeUsecase;
  final ConfigRepository _configRepository;

  GetMealPointsUsageUsecase(this._getIntakeUsecase, this._configRepository);

  Future<MacroPoints> usedIn(IntakeTypeEntity type, DateTime day) async =>
      (await intakesOf(type, day)).macroPoints;

  /// The points logged in each of [slots] on [day], by meal id.
  Future<Map<String, MacroPoints>> usedPerSlot(
    DateTime day,
    List<MealSlot> slots,
  ) async {
    final intakes = [
      for (final type in IntakeTypeEntity.values) ...await intakesOf(type, day),
    ];
    final grouping = locator.isRegistered<MealSlotAssignments>()
        ? locator<MealSlotAssignments>().group(intakes, slots)
        : null;
    return {
      for (final slot in slots)
        slot.id: grouping != null
            ? (grouping.bySlot[slot.id] ?? const <IntakeEntity>[]).macroPoints
            : (slots.defaultFor(slot.baseType)?.id == slot.id
                  ? intakes.where((i) => i.type == slot.baseType).macroPoints
                  : MacroPoints.zero),
    };
  }

  /// The intakes logged as [type] on [day].
  Future<List<IntakeEntity>> intakesOf(
    IntakeTypeEntity type,
    DateTime day,
  ) async {
    final config = await _configRepository.getConfig();
    final hours = config.dayStartOffsetHours;
    final minutes = config.dayStartOffsetMinutes;
    final List<IntakeEntity> intakes;
    switch (type) {
      case IntakeTypeEntity.breakfast:
        intakes = await _getIntakeUsecase.getBreakfastIntakeByDay(
          day,
          dayStartOffsetHours: hours,
          dayStartOffsetMinutes: minutes,
        );
      case IntakeTypeEntity.lunch:
        intakes = await _getIntakeUsecase.getLunchIntakeByDay(
          day,
          dayStartOffsetHours: hours,
          dayStartOffsetMinutes: minutes,
        );
      case IntakeTypeEntity.dinner:
        intakes = await _getIntakeUsecase.getDinnerIntakeByDay(
          day,
          dayStartOffsetHours: hours,
          dayStartOffsetMinutes: minutes,
        );
      case IntakeTypeEntity.snack:
        intakes = await _getIntakeUsecase.getSnackIntakeByDay(
          day,
          dayStartOffsetHours: hours,
          dayStartOffsetMinutes: minutes,
        );
    }
    return intakes;
  }
}
