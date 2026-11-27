import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';
import 'package:opennutritracker/features/meal_closer/domain/meal_closer.dart';
import 'package:opennutritracker/features/points/presentation/points_colors.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// "Still missing: 1.5 protein, 0.5 fat" for [gap].
String closerMissingList(BuildContext context, MealGap gap) {
  final s = S.of(context);
  final format = PointsFormat.of(context);
  return [
    if (gap.hasProtein) s.closerProtein(format.points(gap.macros.protein)),
    if (gap.hasCarbs) s.closerCarbs(format.points(gap.macros.carbs)),
    if (gap.hasFat) s.closerFat(format.points(gap.macros.fat)),
    if (gap.hasFibre) s.closerFibre(format.points(gap.fibre)),
  ].join(', ');
}

/// What a meal still lacks and foods that would complete it.
///
/// With [onPick] the foods can be tapped (to log or add them); without it
/// they are shown as a guide.
class MealCloserPanel extends StatelessWidget {
  final MealGap gap;

  /// The food about to be logged is already counted in [gap].
  final bool afterServing;

  final ValueChanged<CloserSuggestion>? onPick;

  /// Foods not to suggest, by concept (what is already in the meal).
  final Set<String> excludeConcepts;

  final int limit;

  const MealCloserPanel({
    super.key,
    required this.gap,
    this.afterServing = false,
    this.onPick,
    this.excludeConcepts = const {},
    this.limit = 4,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    if (gap.isClosed) {
      return Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: Dimens.spacing8),
          Expanded(
            child: Text(s.closerClosed, style: theme.textTheme.bodySmall),
          ),
        ],
      );
    }
    final knowledge = FoodKnowledge.instance;
    final suggestions = knowledge == null
        ? const <CloserSuggestion>[]
        : MealCloser.suggest(
            gap,
            knowledge,
            limit: limit,
            excludeConcepts: excludeConcepts,
          );
    final list = closerMissingList(context, gap);
    return Semantics(
      identifier: 'meal-closer-panel',
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline_rounded, size: 18),
              const SizedBox(width: Dimens.spacing8),
              Expanded(
                child: Text(
                  afterServing
                      ? s.closerMissingAfter(list)
                      : s.closerMissing(list),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: Dimens.spacing8),
            Text(
              s.closerSuggestionsTitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Dimens.spacing4),
            Wrap(
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing8,
              children: [
                for (final c in suggestions) _SuggestionChip(c, onPick),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final CloserSuggestion suggestion;
  final ValueChanged<CloserSuggestion>? onPick;

  const _SuggestionChip(this.suggestion, this.onPick);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final format = PointsFormat.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final c = suggestion;
    final portion = knowledgePortion(c, lang);
    final amount =
        '${format.grams(c.grams)} g${portion == null ? '' : ' (≈ $portion)'}';
    final dots = <Widget>[
      if (c.points.protein >= 0.125) _dot(palette.protein, c.points.protein),
      if (c.points.carbs >= 0.125) _dot(palette.carbs, c.points.carbs),
      if (c.points.fat >= 0.125) _dot(palette.fat, c.points.fat),
      if (c.fibre >= 0.125) _dot(PointsColors.fibre, c.fibre),
    ];
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing12,
        vertical: Dimens.spacing8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(c.food.name(lang), style: theme.textTheme.labelLarge),
          Text(amount, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Builder(
            builder: (context) => DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall,
              child: Wrap(spacing: Dimens.spacing8, children: dots),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      identifier: 'meal-closer-${c.food.id}',
      button: onPick != null,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: Dimens.borderRadiusM,
        child: onPick == null
            ? content
            : InkWell(
                borderRadius: Dimens.borderRadiusM,
                onTap: () => onPick!(c),
                child: content,
              ),
      ),
    );
  }

  Widget _dot(Color color, double value) => Builder(
    builder: (context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(PointsFormat.of(context).points(value)),
      ],
    ),
  );
}

/// "1½ fillets" for a suggestion, or null when the food has no household
/// unit that fits.
String? knowledgePortion(CloserSuggestion c, String languageCode) {
  final portion = FoodKnowledge.instance
      ?.conceptById(c.food.conceptId)
      ?.mainPortion;
  if (portion == null) return null;
  return PortionFormatter.describe(c.grams, portion)?.label(languageCode);
}
