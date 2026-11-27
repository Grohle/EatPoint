import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/insights/domain/week_insights.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The title and explanation of an [Insight] in the user's language.
({String title, String body, IconData icon}) insightText(
  BuildContext context,
  Insight insight,
) {
  final s = S.of(context);
  final format = PointsFormat.of(context);
  String v(String key) {
    final value = insight.values[key];
    if (value == null) return '';
    return value is int ? '$value' : format.points(value.toDouble());
  }

  switch (insight.kind) {
    case InsightKind.fibreLow:
      return (
        title: s.insightFibreLowTitle,
        body: s.insightFibreLowBody(v('avg'), v('target')),
        icon: Icons.grass_rounded,
      );
    case InsightKind.fibreGood:
      return (
        title: s.insightFibreGoodTitle,
        body: s.insightFibreGoodBody(v('avg')),
        icon: Icons.grass_rounded,
      );
    case InsightKind.oilyFishMissing:
      return (
        title: s.insightOilyFishTitle,
        body: s.insightOilyFishBody(v('fish')),
        icon: Icons.set_meal_rounded,
      );
    case InsightKind.oilyFishGood:
      return (
        title: s.insightOilyFishGoodTitle,
        body: s.insightOilyFishGoodBody(v('fish')),
        icon: Icons.set_meal_rounded,
      );
    case InsightKind.plantOmega3:
      return (
        title: s.insightPlantOmega3Title,
        body: s.insightPlantOmega3Body,
        icon: Icons.spa_rounded,
      );
    case InsightKind.b12Missing:
      return (
        title: s.insightB12Title,
        body: s.insightB12Body,
        icon: Icons.medication_outlined,
      );
    case InsightKind.legumesLow:
      return (
        title: s.insightLegumesTitle,
        body: s.insightLegumesBody(v('count')),
        icon: Icons.eco_rounded,
      );
    case InsightKind.legumesGood:
      return (
        title: s.insightLegumesGoodTitle,
        body: s.insightLegumesGoodBody(v('count')),
        icon: Icons.eco_rounded,
      );
    case InsightKind.fruitVegLow:
      return (
        title: s.insightFruitVegTitle,
        body: s.insightFruitVegBody(v('grams'), v('servings')),
        icon: Icons.local_florist_rounded,
      );
    case InsightKind.fruitVegGood:
      return (
        title: s.insightFruitVegGoodTitle,
        body: s.insightFruitVegGoodBody(v('grams')),
        icon: Icons.local_florist_rounded,
      );
    case InsightKind.wholegrainLow:
      return (
        title: s.insightWholegrainTitle,
        body: s.insightWholegrainBody(v('whole'), v('total')),
        icon: Icons.bakery_dining_outlined,
      );
    case InsightKind.varietyLow:
      return (
        title: s.insightVarietyTitle,
        body: s.insightVarietyBody(insight.food ?? '', v('days')),
        icon: Icons.shuffle_rounded,
      );
    case InsightKind.processedMeatHigh:
      return (
        title: s.insightProcessedMeatTitle,
        body: s.insightProcessedMeatBody(v('count')),
        icon: Icons.lunch_dining_outlined,
      );
    case InsightKind.sweetsHigh:
      return (
        title: s.insightSweetsTitle,
        body: s.insightSweetsBody(v('count')),
        icon: Icons.cake_outlined,
      );
    case InsightKind.calciumLow:
      return (
        title: s.insightCalciumTitle,
        body: s.insightCalciumBody,
        icon: Icons.local_drink_outlined,
      );
  }
}

/// A card at the top of the weekly menu: how many suggestions the week has
/// and the first of them; tapping it lists them all.
class WeekInsightsCard extends StatelessWidget {
  final List<DayPlan> week;
  final double fibreTargetPoints;

  const WeekInsightsCard({
    super.key,
    required this.week,
    required this.fibreTargetPoints,
  });

  @override
  Widget build(BuildContext context) {
    final knowledge = FoodKnowledge.instance;
    if (knowledge == null) return const SizedBox.shrink();
    final s = S.of(context);
    final theme = Theme.of(context);
    final insights = WeekInsights.analyse(
      week,
      knowledge: knowledge,
      fibreTargetPoints: fibreTargetPoints,
    );
    if (insights.isEmpty) {
      if (WeekInsights.plannedDays(week).isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: Dimens.spacing8),
        child: Text(
          s.insightNeedMoreDays(WeekInsights.minDays.toString()),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final suggestions = insights.where((i) => i.isSuggestion).toList();
    final first = insightText(context, insights.first);
    return Padding(
      padding: const EdgeInsets.only(top: Dimens.spacing8),
      child: Semantics(
        identifier: 'week-insights-card',
        button: true,
        child: Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
          child: InkWell(
            borderRadius: Dimens.borderRadiusL,
            onTap: () => showWeekInsights(context, insights),
            child: Padding(
              padding: const EdgeInsets.all(Dimens.spacing12),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline_rounded),
                  const SizedBox(width: Dimens.spacing12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestions.isEmpty
                              ? s.insightCardAllGood
                              : s.insightCardTitle(
                                  suggestions.length.toString(),
                                ),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          first.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lists every insight of the week, suggestions first.
Future<void> showWeekInsights(BuildContext context, List<Insight> insights) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final s = S.of(context);
      final theme = Theme.of(context);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            0,
            Dimens.spacing16,
            Dimens.spacing24,
          ),
          children: [
            Text(s.insightSheetTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: Dimens.spacing8),
            for (final insight in insights)
              Builder(
                builder: (context) {
                  final text = insightText(context, insight);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: insight.isSuggestion
                          ? const Color(0xFFFFB300).withValues(alpha: 0.25)
                          : theme.colorScheme.primary.withValues(alpha: 0.15),
                      child: Icon(text.icon, size: 20),
                    ),
                    title: Text(text.title),
                    subtitle: Text(text.body),
                  );
                },
              ),
            const SizedBox(height: Dimens.spacing8),
            Text(
              s.insightGuideOnly,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    },
  );
}
