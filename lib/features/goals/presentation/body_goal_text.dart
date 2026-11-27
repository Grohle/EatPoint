import 'package:flutter/material.dart';
import 'package:opennutritracker/features/goals/domain/body_goal.dart';
import 'package:opennutritracker/generated/l10n.dart';

extension BodyGoalText on BodyGoal {
  String name(BuildContext context) {
    final s = S.of(context);
    return switch (this) {
      BodyGoal.loseWeight => s.goalLoseWeight,
      BodyGoal.loseWeightBuildMuscle => s.goalLoseWeightBuildMuscle,
      BodyGoal.maintainWeight => s.goalMaintainWeight,
      BodyGoal.buildMuscle => s.goalBuildMuscle,
      BodyGoal.gainWeightAndMuscle => s.goalGainWeightAndMuscle,
      BodyGoal.gainWeight => s.goalGainWeight,
    };
  }

  String description(BuildContext context) {
    final s = S.of(context);
    return switch (this) {
      BodyGoal.loseWeight => s.goalLoseWeightDescription,
      BodyGoal.loseWeightBuildMuscle => s.goalLoseWeightBuildMuscleDescription,
      BodyGoal.maintainWeight => s.goalMaintainWeightDescription,
      BodyGoal.buildMuscle => s.goalBuildMuscleDescription,
      BodyGoal.gainWeightAndMuscle => s.goalGainWeightAndMuscleDescription,
      BodyGoal.gainWeight => s.goalGainWeightDescription,
    };
  }

  IconData get icon => switch (this) {
    BodyGoal.loseWeight => Icons.trending_down_rounded,
    BodyGoal.loseWeightBuildMuscle => Icons.compare_arrows_rounded,
    BodyGoal.maintainWeight => Icons.trending_flat_rounded,
    BodyGoal.buildMuscle => Icons.fitness_center_rounded,
    BodyGoal.gainWeightAndMuscle => Icons.sports_gymnastics_rounded,
    BodyGoal.gainWeight => Icons.trending_up_rounded,
  };
}
