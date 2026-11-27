import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/goals/domain/body_goal.dart';
import 'package:opennutritracker/features/goals/presentation/body_goal_text.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/goal_suggestion_entity.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/user_goal_selection_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';

class OnboardingGoalPageBody extends StatefulWidget {
  final Function(bool active, UserGoalSelectionEntity? selectedGoal)
  setButtonContent;
  final UserGoalSelectionEntity? initialGoal;

  /// Entered on the previous pages, and used only to derive the suggestion.
  /// Without them the page shows no suggestion.
  final double? heightCm;
  final double? weightKg;
  final double? targetWeightKg;

  /// EatPoint: the muscle goals. Whether the earlier choice included
  /// building muscle, and where the full choice goes.
  final bool initialBuildMuscle;
  final ValueChanged<BodyGoal>? onBodyGoalChanged;

  const OnboardingGoalPageBody({
    super.key,
    required this.setButtonContent,
    this.initialGoal,
    this.heightCm,
    this.weightKg,
    this.targetWeightKg,
    this.initialBuildMuscle = false,
    this.onBodyGoalChanged,
  });

  @override
  State<OnboardingGoalPageBody> createState() => _OnboardingGoalPageBodyState();
}

class _OnboardingGoalPageBodyState extends State<OnboardingGoalPageBody> {
  late BodyGoal? _selected = switch (widget.initialGoal) {
    null => null,
    final goal => BodyGoal.of(
      _weightGoalOf(goal),
      buildMuscle: widget.initialBuildMuscle,
    ),
  };

  static UserWeightGoalEntity _weightGoalOf(UserGoalSelectionEntity goal) =>
      switch (goal) {
        UserGoalSelectionEntity.loseWeight => UserWeightGoalEntity.loseWeight,
        UserGoalSelectionEntity.maintainWeight =>
          UserWeightGoalEntity.maintainWeight,
        UserGoalSelectionEntity.gainWeigh => UserWeightGoalEntity.gainWeight,
      };

  static UserGoalSelectionEntity _selectionOf(BodyGoal goal) =>
      switch (goal.weightGoal) {
        UserWeightGoalEntity.loseWeight => UserGoalSelectionEntity.loseWeight,
        UserWeightGoalEntity.maintainWeight =>
          UserGoalSelectionEntity.maintainWeight,
        UserWeightGoalEntity.gainWeight => UserGoalSelectionEntity.gainWeigh,
      };

  /// Derived on every build rather than cached, so going back to the
  /// height/weight page and changing a value can't leave the badge marking
  /// the goal the old numbers pointed at. It is pure arithmetic on three
  /// doubles, so there is nothing to save by holding on to it.
  GoalSuggestionEntity? get _suggestion => GoalSuggestionEntity.from(
    heightCm: widget.heightCm,
    weightKg: widget.weightKg,
    targetWeightKg: widget.targetWeightKg,
  );

  static const _identifierSuffix = {
    BodyGoal.loseWeight: 'lose',
    BodyGoal.loseWeightBuildMuscle: 'lose-muscle',
    BodyGoal.maintainWeight: 'maintain',
    BodyGoal.buildMuscle: 'muscle',
    BodyGoal.gainWeightAndMuscle: 'gain-muscle',
    BodyGoal.gainWeight: 'gain',
  };

  @override
  Widget build(BuildContext context) {
    final suggestion = _suggestion;
    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).goalLabel,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              S.of(context).onboardingGoalQuestionSubtitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Dimens.spacing16),
            for (final goal in BodyGoal.values) ...[
              _buildGoalRow(goal, suggestion),
              const SizedBox(height: Dimens.spacing8),
            ],
            if (suggestion != null) ...[
              const SizedBox(height: Dimens.spacing8),
              _buildSuggestionCard(suggestion),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGoalRow(BodyGoal goal, GoalSuggestionEntity? suggestion) {
    final isSuggested =
        !goal.buildsMuscle && suggestion?.goal == _selectionOf(goal);
    final theme = Theme.of(context);
    // A Wrap: at a large font the badge moves under the chip rather than
    // overflowing the row.
    final row = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Dimens.spacing8,
      runSpacing: Dimens.spacing4,
      children: [
        Semantics(
          identifier: 'onboarding-goal-${_identifierSuffix[goal]}',
          child: ChoiceChip(
            avatar: Icon(goal.icon),
            label: Text(goal.name(context), style: theme.textTheme.titleLarge),
            selected: _selected == goal,
            onSelected: (_) => _onSelected(goal),
          ),
        ),
        if (isSuggested) _buildSuggestedBadge(),
      ],
    );
    // EatPoint: what each goal means, under its chip once chosen.
    if (_selected != goal) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing8,
            Dimens.spacing4,
            Dimens.spacing8,
            0,
          ),
          child: Text(
            goal.description(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// Marks the suggested option without selecting it. The user still makes
  /// the choice, with the numbers' direction stated.
  Widget _buildSuggestedBadge() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing8,
        vertical: Dimens.spacing4,
      ),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(Dimens.radiusS),
      ),
      child: Text(
        S.of(context).onboardingGoalSuggestedBadge,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.onSecondaryContainer),
      ),
    );
  }

  /// States what the suggestion rests on, so it reads as a derivation rather
  /// than an opinion the app is handing down.
  Widget _buildSuggestionCard(GoalSuggestionEntity suggestion) {
    final String reason;
    switch (suggestion.basis) {
      case GoalSuggestionBasis.targetWeight:
        reason = S.of(context).onboardingGoalSuggestionTarget;
      case GoalSuggestionBasis.bmi:
        reason = S
            .of(context)
            .onboardingGoalSuggestionBmi(
              suggestion.bmi!.toStringAsFixed(1),
              suggestion.nutritionalStatus!.getName(context),
            );
    }

    return Container(
      padding: const EdgeInsets.all(Dimens.spacing12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Dimens.radiusS),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: Dimens.spacing8),
          Expanded(
            child: Text(reason, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  void _onSelected(BodyGoal goal) {
    setState(() => _selected = goal);
    widget.setButtonContent(true, _selectionOf(goal));
    widget.onBodyGoalChanged?.call(goal);
  }
}
