import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';

/// What the user wants from their body: the weight goal the rest of the
/// app knows (lose, maintain, gain) and whether they also want to build
/// muscle.
///
/// The muscle part is EatPoint's own and lives in the points settings
/// (`PointsSettings.buildMuscle`), so the stored profile keeps its three
/// weight goals.
enum BodyGoal {
  loseWeight(UserWeightGoalEntity.loseWeight, buildsMuscle: false),

  /// Lose fat while building muscle ("recomposition"): a gentle deficit
  /// and plenty of protein.
  loseWeightBuildMuscle(UserWeightGoalEntity.loseWeight, buildsMuscle: true),

  maintainWeight(UserWeightGoalEntity.maintainWeight, buildsMuscle: false),

  /// Build muscle with as little fat as possible: a small surplus.
  buildMuscle(UserWeightGoalEntity.gainWeight, buildsMuscle: true),

  /// Gain weight and muscle: a larger surplus.
  gainWeightAndMuscle(UserWeightGoalEntity.gainWeight, buildsMuscle: true),

  gainWeight(UserWeightGoalEntity.gainWeight, buildsMuscle: false);

  final UserWeightGoalEntity weightGoal;
  final bool buildsMuscle;

  const BodyGoal(this.weightGoal, {required this.buildsMuscle});

  /// Protein, in grams per kg of lean mass, the muscle goals ask for at
  /// least. A deficit needs more to keep the muscle there is.
  static const muscleProteinPerKgLeanMass = 2.2;
  static const recompositionProteinPerKgLeanMass = 2.4;

  /// The same goals in grams per kg of body weight, for the calorie-goal
  /// method, which has no lean-mass estimate.
  static const muscleProteinPerKgBodyWeight = 1.8;
  static const recompositionProteinPerKgBodyWeight = 2.0;

  /// The goal the profile's weight goal and the muscle setting describe.
  /// "Gain weight" with muscle reads as [gainWeightAndMuscle] unless the
  /// weekly pace is the gentle one of [buildMuscle].
  static BodyGoal of(
    UserWeightGoalEntity goal, {
    required bool buildMuscle,
    double? weeklyPaceKg,
  }) {
    switch (goal) {
      case UserWeightGoalEntity.loseWeight:
        return buildMuscle ? loseWeightBuildMuscle : loseWeight;
      case UserWeightGoalEntity.maintainWeight:
        return maintainWeight;
      case UserWeightGoalEntity.gainWeight:
        if (!buildMuscle) return gainWeight;
        return weeklyPaceKg != null &&
                weeklyPaceKg <= BodyGoal.buildMuscle.defaultWeeklyPaceKg
            ? BodyGoal.buildMuscle
            : gainWeightAndMuscle;
    }
  }

  /// The weekly pace that goes with the goal, in kg a week.
  double get defaultWeeklyPaceKg => switch (this) {
    loseWeight => -0.5,
    loseWeightBuildMuscle => -0.25,
    maintainWeight => 0.0,
    buildMuscle => 0.25,
    gainWeightAndMuscle => 0.5,
    gainWeight => 0.5,
  };

  /// Calories to eat, as a share of maintenance, in the lean-mass method.
  double get leanMassCalorieAdjustment => switch (this) {
    loseWeight => 0.75,
    loseWeightBuildMuscle => 0.85,
    maintainWeight => 1.0,
    buildMuscle => 1.05,
    gainWeightAndMuscle => 1.10,
    gainWeight => 1.10,
  };

  /// The least protein per kg of lean mass the goal asks for, or null when
  /// the user's own setting stands.
  double? get minProteinPerKgLeanMass => !buildsMuscle
      ? null
      : this == loseWeightBuildMuscle
      ? recompositionProteinPerKgLeanMass
      : muscleProteinPerKgLeanMass;

  /// The least protein per kg of body weight, for the calorie-goal method.
  double? get minProteinPerKgBodyWeight => !buildsMuscle
      ? null
      : this == loseWeightBuildMuscle
      ? recompositionProteinPerKgBodyWeight
      : muscleProteinPerKgBodyWeight;
}
