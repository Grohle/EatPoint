import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/meal_closer/domain/meal_closer.dart';
import 'package:opennutritracker/features/meal_closer/presentation/meal_closer_panel.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// In the recipe builder: one serving of the recipe against the budget of
/// one of the user's meals, what it lacks or goes over, and foods to
/// complete it, added to the recipe with a tap.
class RecipeBalancePanel extends StatefulWidget {
  /// Nutrition of the whole recipe per 100 g, its weight and servings.
  final MealNutrimentsEntity per100;
  final double totalWeightG;
  final int? servings;

  /// The names of the ingredients, so they are not suggested again.
  final List<String> ingredientNames;

  /// Adds [grams] of [meal] to the recipe (for all servings).
  final void Function(MealEntity meal, double grams) onAdd;

  const RecipeBalancePanel({
    super.key,
    required this.per100,
    required this.totalWeightG,
    required this.servings,
    required this.ingredientNames,
    required this.onAdd,
  });

  @override
  State<RecipeBalancePanel> createState() => _RecipeBalancePanelState();
}

class _RecipeBalancePanelState extends State<RecipeBalancePanel> {
  PointsBudgetResult? _budget;
  String? _slotId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!locator.isRegistered<GetPointsBudgetUsecase>()) return;
    try {
      final budget = await locator<GetPointsBudgetUsecase>().getBudget();
      if (!mounted) return;
      setState(() {
        _budget = budget;
        // The biggest meal is the likeliest home for a recipe.
        final slots = [...budget.slots]
          ..sort(
            (a, b) => (budget.perSlot[b.id]?.total ?? 0).compareTo(
              budget.perSlot[a.id]?.total ?? 0,
            ),
          );
        _slotId = slots.firstOrNull?.id;
      });
    } catch (_) {}
  }

  int get _servings {
    final n = widget.servings;
    return n == null || n < 1 ? 1 : n;
  }

  @override
  Widget build(BuildContext context) {
    final budget = _budget;
    final slotId = _slotId;
    if (budget == null || slotId == null || widget.totalWeightG <= 0) {
      return const SizedBox.shrink();
    }
    final s = S.of(context);
    final theme = Theme.of(context);
    final format = PointsFormat.of(context);
    final slotBudget = budget.perSlot[slotId] ?? MacroPoints.zero;
    final servingGrams = widget.totalWeightG / _servings;
    final serving = widget.per100.macroPointsFor(servingGrams);
    final servingFibre = widget.per100.fibrePointsFor(servingGrams);
    final gap = MealGap.of(
      budget: slotBudget,
      used: serving,
      fibreTarget: budget.fibrePerSlot[slotId] ?? 0,
      fibreUsed: servingFibre,
    );
    final over = slotBudget - serving;
    final overParts = [
      if (over.protein <= -MealGap.threshold)
        s.closerProtein(format.points(-over.protein)),
      if (over.carbs <= -MealGap.threshold)
        s.closerCarbs(format.points(-over.carbs)),
      if (over.fat <= -MealGap.threshold) s.closerFat(format.points(-over.fat)),
    ];
    final knowledge = FoodKnowledge.instance;
    final inRecipe = <String>{
      for (final name in widget.ingredientNames) ?knowledge?.match(name)?.id,
    };
    return Semantics(
      identifier: 'recipe-balance-panel',
      container: true,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Dimens.spacing12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.closerRecipeTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: Dimens.spacing8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.closerRecipeAgainst,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  DropdownButton<String>(
                    value: slotId,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final MealSlot slot in budget.slots)
                        DropdownMenuItem(
                          value: slot.id,
                          child: Text(mealSlotLabel(context, slot)),
                        ),
                    ],
                    onChanged: (id) => setState(() => _slotId = id),
                  ),
                ],
              ),
              Text(
                '${format.points(serving.total)} / '
                '${format.points(slotBudget.total)} ${s.pointsShort}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Dimens.spacing8),
              if (overParts.isNotEmpty) ...[
                Text(
                  s.closerRecipeOver(overParts.join(', ')),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: Dimens.spacing8),
              ],
              MealCloserPanel(
                gap: gap,
                excludeConcepts: inRecipe,
                onPick: (c) {
                  final lang = Localizations.localeOf(context).languageCode;
                  widget.onAdd(c.food.toMealEntity(lang), c.grams * _servings);
                },
              ),
              if (!gap.isClosed) ...[
                const SizedBox(height: Dimens.spacing8),
                Text(
                  s.closerRecipeHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
