import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/features/points/presentation/points_settings_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Presents the suggested daily points budget the first time points are
/// used, with the note that it is a guide only.
class PointsBudgetGuideSheet extends StatelessWidget {
  final PointsBudgetResult budget;

  const PointsBudgetGuideSheet({super.key, required this.budget});

  static Future<void> show(BuildContext context, PointsBudgetResult budget) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PointsBudgetGuideSheet(budget: budget),
    );
  }

  Future<void> _acknowledge() async {
    final source = locator<PointsSettingsDataSource>();
    final settings = await source.getSettings();
    await source.saveSettings(settings.copyWith(budgetGuideAcknowledged: true));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final format = PointsFormat.of(context);
    final daily = budget.daily;

    Widget macro(String label, Color color, double value) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(Dimens.spacing12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: Dimens.borderRadiusM,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            Text(
              '${format.points(value)} ${s.pointsShort}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing24,
          0,
          Dimens.spacing24,
          Dimens.spacing24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.pointsGuideTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: Dimens.spacing16),
            Text(
              '${format.points(daily.total)} ${s.pointsShort}',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              s.pointsSuggestedKcal(
                budget.suggestion.kcalGoal.round().toString(),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            Row(
              children: [
                macro(s.pointsCarbsLabel, palette.carbs, daily.carbs),
                const SizedBox(width: Dimens.spacing8),
                macro(s.pointsProteinLabel, palette.protein, daily.protein),
                const SizedBox(width: Dimens.spacing8),
                macro(s.pointsFatLabel, palette.fat, daily.fat),
              ],
            ),
            const SizedBox(height: Dimens.spacing16),
            Container(
              padding: const EdgeInsets.all(Dimens.spacing12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: Dimens.borderRadiusM,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Dimens.spacing8),
                  Expanded(
                    child: Text(
                      s.pointsGuideBody,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Dimens.spacing24),
            Row(
              children: [
                Semantics(
                  identifier: 'points-guide-adjust',
                  child: OutlinedButton(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      await _acknowledge();
                      navigator.pop();
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => const PointsSettingsScreen(),
                        ),
                      );
                    },
                    child: Text(s.pointsGuideAdjust),
                  ),
                ),
                const SizedBox(width: Dimens.spacing12),
                Expanded(
                  child: Semantics(
                    identifier: 'points-guide-accept',
                    child: FilledButton(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        await _acknowledge();
                        navigator.pop();
                      },
                      child: Text(s.pointsGuideAccept),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
