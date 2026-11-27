import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/goals/domain/body_goal.dart';
import 'package:opennutritracker/features/goals/presentation/body_goal_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Lets the user pick one of the six goals, each with what it means.
class BodyGoalDialog extends StatelessWidget {
  final BodyGoal? current;

  const BodyGoalDialog({super.key, this.current});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(s.chooseWeightGoalLabel),
      contentPadding: const EdgeInsets.fromLTRB(0, Dimens.spacing12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final goal in BodyGoal.values)
              Semantics(
                identifier: 'body-goal-${goal.name}',
                selected: goal == current,
                child: ListTile(
                  leading: Icon(goal.icon),
                  title: Text(goal.name(context)),
                  subtitle: Text(goal.description(context)),
                  selected: goal == current,
                  trailing: goal == current
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, goal),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing24,
                Dimens.spacing8,
                Dimens.spacing24,
                0,
              ),
              child: Text(
                s.goalProteinNote(
                  _format(context, BodyGoal.muscleProteinPerKgLeanMass),
                  _format(context, BodyGoal.muscleProteinPerKgBodyWeight),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }

  static String _format(BuildContext context, double value) {
    final text = value.toStringAsFixed(1);
    final decimalComma = Localizations.localeOf(context).languageCode == 'es';
    return decimalComma ? text.replaceAll('.', ',') : text;
  }
}
