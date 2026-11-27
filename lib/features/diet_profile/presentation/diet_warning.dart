import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/diet_profile/data/diet_profile_store.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_text.dart';
import 'package:opennutritracker/generated/l10n.dart';

Color dietSeverityColor(BuildContext context, ConflictSeverity severity) {
  final scheme = Theme.of(context).colorScheme;
  return switch (severity) {
    ConflictSeverity.avoid => scheme.error,
    ConflictSeverity.adapt => const Color(0xFFB7791F),
    ConflictSeverity.note => scheme.primary,
  };
}

IconData dietSeverityIcon(ConflictSeverity severity) => switch (severity) {
  ConflictSeverity.avoid => Icons.block_rounded,
  ConflictSeverity.adapt => Icons.swap_horiz_rounded,
  ConflictSeverity.note => Icons.info_outline_rounded,
};

/// Warns when [foodName] goes against the user's diet profile: what it
/// contains, why it matters and what to choose instead. Nothing when it
/// fits or no profile is set up.
class DietWarning extends StatelessWidget {
  final String foodName;
  final String? conceptId;

  /// Checker to use; the active profile's when null.
  final DietChecker? checker;

  /// Space around the warning, only when it shows.
  final EdgeInsetsGeometry margin;

  /// Names the food in the title, for lists of several.
  final bool showName;

  const DietWarning(
    this.foodName, {
    super.key,
    this.conceptId,
    this.checker,
    this.margin = EdgeInsets.zero,
    this.showName = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = checker ?? DietProfileStore.checker();
    if (c == null) return const SizedBox.shrink();
    final conflicts = c.check(foodName, conceptId: conceptId);
    if (conflicts.isEmpty) return const SizedBox.shrink();
    final s = S.of(context);
    final theme = Theme.of(context);
    final worst = conflicts.first.severity;
    final color = dietSeverityColor(context, worst);
    final title = switch (worst) {
      ConflictSeverity.avoid => s.dietWarnAvoid,
      ConflictSeverity.adapt => s.dietWarnAdapt,
      ConflictSeverity.note => s.dietWarnNote,
    };
    return Semantics(
      identifier: 'diet-warning',
      container: true,
      child: Container(
        margin: margin,
        width: double.infinity,
        padding: const EdgeInsets.all(Dimens.spacing12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: Dimens.borderRadiusM,
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(dietSeverityIcon(worst), size: 18, color: color),
                const SizedBox(width: Dimens.spacing8),
                Expanded(
                  child: Text(
                    showName ? '$foodName · $title' : title,
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Dimens.spacing4),
            for (final conflict in conflicts)
              Builder(
                builder: (context) {
                  final text = dietConflictText(context, c.profile, conflict);
                  return Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      text.alternative == null
                          ? '• ${text.reason}'
                          : '• ${text.reason}. ${text.alternative}',
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                },
              ),
            if (conflicts.any((x) => x.trait != null))
              Padding(
                padding: const EdgeInsets.only(top: Dimens.spacing4),
                child: Text(
                  s.dietCheckLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A compact icon for lists, coloured by the most serious conflict, with
/// the reasons as its tooltip. Nothing when [foodName] fits.
class DietBadge extends StatelessWidget {
  final String foodName;
  final String? conceptId;
  final DietChecker? checker;

  const DietBadge(this.foodName, {super.key, this.conceptId, this.checker});

  @override
  Widget build(BuildContext context) {
    final c = checker ?? DietProfileStore.checker();
    if (c == null) return const SizedBox.shrink();
    final conflicts = c
        .check(foodName, conceptId: conceptId)
        .where((x) => x.severity != ConflictSeverity.note)
        .toList();
    if (conflicts.isEmpty) return const SizedBox.shrink();
    final worst = conflicts.first.severity;
    final tooltip = [
      for (final x in conflicts) dietConflictText(context, c.profile, x).reason,
    ].join('\n');
    return Semantics(
      identifier: 'diet-badge',
      child: Tooltip(
        message: tooltip,
        child: Icon(
          dietSeverityIcon(worst),
          size: 18,
          color: dietSeverityColor(context, worst),
        ),
      ),
    );
  }
}

/// Asks before adding a food that must be avoided. True to go ahead;
/// always true when nothing must be avoided.
Future<bool> confirmDietConflicts(
  BuildContext context,
  String foodName, {
  String? conceptId,
}) async {
  final c = DietProfileStore.checker();
  if (c == null || !c.blocks(foodName, conceptId: conceptId)) return true;
  final s = S.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(foodName),
      content: DietWarning(foodName, conceptId: conceptId, checker: c),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(s.dietAddAnyway),
        ),
      ],
    ),
  );
  return ok ?? false;
}
