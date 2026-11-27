import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/features/goals/domain/body_goal.dart';

/// Keeps the weekly pace in line with the weight goal.
///
/// A set weekly pace wins over the goal when the calorie target is worked
/// out, so a pace that points the other way (for example "maintain" after
/// choosing to lose weight) would leave the target where it was.
class WeeklyPaceForGoal {
  WeeklyPaceForGoal._();

  /// The pace that goes with [goal] when the old one no longer fits: about
  /// half a kilo a week to lose or gain, none to maintain.
  static double defaultKg(UserWeightGoalEntity goal) => switch (goal) {
    UserWeightGoalEntity.loseWeight => BodyGoal.loseWeight.defaultWeeklyPaceKg,
    UserWeightGoalEntity.gainWeight => BodyGoal.gainWeight.defaultWeeklyPaceKg,
    UserWeightGoalEntity.maintainWeight =>
      BodyGoal.maintainWeight.defaultWeeklyPaceKg,
  };

  /// Whether [paceKg] points away from [goal]. No pace set never does.
  static bool contradicts(UserWeightGoalEntity goal, double? paceKg) {
    if (paceKg == null) return false;
    return switch (goal) {
      UserWeightGoalEntity.loseWeight => paceKg >= 0,
      UserWeightGoalEntity.gainWeight => paceKg <= 0,
      UserWeightGoalEntity.maintainWeight => paceKg != 0,
    };
  }

  /// The pace to keep after the goal changes to [goal]: [paceKg] when it
  /// still fits, otherwise [defaultKg].
  static double? adjust(UserWeightGoalEntity goal, double? paceKg) =>
      contradicts(goal, paceKg) ? defaultKg(goal) : paceKg;

  /// The pace after the goal changes from [previous] to [next]: the pace
  /// of [next] when the old one points the other way or a muscle goal is
  /// involved (they differ only in pace and protein), otherwise [paceKg].
  static double? adjustBodyGoal(
    BodyGoal previous,
    BodyGoal next,
    double? paceKg,
  ) {
    if (previous == next) return paceKg;
    if (next.buildsMuscle ||
        previous.buildsMuscle ||
        contradicts(next.weightGoal, paceKg)) {
      return next.defaultWeeklyPaceKg;
    }
    return paceKg;
  }
}
