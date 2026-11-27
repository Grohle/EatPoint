import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// What an (i) button explains.
enum BudgetInfoTopic {
  /// Points or the classic calorie view.
  points,

  /// The lean-mass, protein-first method.
  leanMass,

  /// The calorie-goal method.
  calories;

  static BudgetInfoTopic forMethod(PointsBudgetMethod method) =>
      switch (method) {
        PointsBudgetMethod.leanMass => leanMass,
        PointsBudgetMethod.appMacros => calories,
      };
}

/// Explains, step by step, how one way of measuring works. With
/// [showBreakdown] the calorie sheet links to today's numbers (not during
/// onboarding, before there is a profile to show).
Future<void> showBudgetInfo(
  BuildContext context,
  BudgetInfoTopic topic, {
  bool showBreakdown = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final s = S.of(context);
      final theme = Theme.of(context);
      final (title, body) = switch (topic) {
        BudgetInfoTopic.points => (
          s.budgetInfoPointsTitle,
          s.budgetInfoPointsBody,
        ),
        BudgetInfoTopic.leanMass => (
          s.budgetInfoLeanMassTitle,
          s.budgetInfoLeanMassBody,
        ),
        BudgetInfoTopic.calories => (
          s.budgetInfoCaloriesTitle,
          s.budgetInfoCaloriesBody,
        ),
      };
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing24,
            0,
            Dimens.spacing24,
            Dimens.spacing24,
          ),
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: Dimens.spacing12),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Dimens.spacing16),
            Text(
              s.budgetInfoGuideOnly,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (topic == BudgetInfoTopic.calories && showBreakdown) ...[
              const SizedBox(height: Dimens.spacing8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(Icons.calculate_outlined),
                  label: Text(s.budgetInfoSeeCalorieBreakdown),
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    navigator.push(
                      MaterialPageRoute(
                        builder: (_) => const KcalGoalInfoScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// The (i) next to a way of measuring.
class BudgetInfoButton extends StatelessWidget {
  final BudgetInfoTopic topic;
  final bool showBreakdown;

  const BudgetInfoButton(this.topic, {super.key, this.showBreakdown = true});

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: 'budget-info-${topic.name}',
    child: IconButton(
      icon: const Icon(Icons.info_outline_rounded),
      tooltip: S.of(context).budgetInfoTooltip,
      onPressed: () =>
          showBudgetInfo(context, topic, showBreakdown: showBreakdown),
    ),
  );
}
