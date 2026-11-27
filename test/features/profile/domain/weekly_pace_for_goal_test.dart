import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/features/profile/domain/weekly_pace_for_goal.dart';

void main() {
  group('WeeklyPaceForGoal', () {
    test('a maintain pace no longer holds back a goal to lose weight', () {
      const goal = UserWeightGoalEntity.loseWeight;
      final pace = WeeklyPaceForGoal.adjust(goal, 0.0);
      expect(pace, -0.5);
      expect(
        CalorieGoalCalc.getKcalGoalAdjustment(goal, weeklyWeightGoalKg: pace),
        lessThan(0),
      );
    });

    test('a pace that already fits the goal is kept', () {
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.loseWeight, -0.25),
        -0.25,
      );
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.gainWeight, 0.5),
        0.5,
      );
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.maintainWeight, 0.0),
        0.0,
      );
    });

    test('a pace pointing the other way follows the goal', () {
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.gainWeight, -0.5),
        0.25,
      );
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.maintainWeight, -0.5),
        0.0,
      );
      expect(
        WeeklyPaceForGoal.adjust(UserWeightGoalEntity.loseWeight, 0.25),
        -0.5,
      );
    });

    test('no pace set stays unset', () {
      for (final goal in UserWeightGoalEntity.values) {
        expect(WeeklyPaceForGoal.adjust(goal, null), isNull);
        expect(WeeklyPaceForGoal.contradicts(goal, null), isFalse);
      }
    });
  });
}
