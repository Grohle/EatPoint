import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';

/// Keeps the weekly pace in line with the weight goal.
///
/// A set weekly pace wins over the goal when the calorie target is worked
/// out, so a pace that points the other way (for example "maintain" after
/// choosing to lose weight) would leave the target where it was.
class WeeklyPaceForGoal {
  WeeklyPaceForGoal._();

  /// The pace that goes with [goal] when the old one no longer fits: about
  /// half a kilo a week to lose, a quarter to gain, none to maintain.
  static double defaultKg(UserWeightGoalEntity goal) => switch (goal) {
    UserWeightGoalEntity.loseWeight => -0.5,
    UserWeightGoalEntity.gainWeight => 0.25,
    UserWeightGoalEntity.maintainWeight => 0.0,
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
}
