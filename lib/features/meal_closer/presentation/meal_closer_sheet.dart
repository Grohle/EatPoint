import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/meal_closer/domain/meal_closer.dart';
import 'package:opennutritracker/features/meal_closer/presentation/meal_closer_panel.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/points/data/meal_slot_assignments.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Lists each meal logged today that is not yet complete, what it lacks
/// and foods to complete it; tapping a food opens it to log in that meal
/// with the suggested amount.
Future<void> showMealCloserSheet(
  BuildContext context, {
  required List<MealSlot> slots,
  required Map<String, MacroPoints> budgets,
  required Map<String, MacroPoints> used,
  required Map<String, double> fibreTargets,
  required Map<String, List<IntakeEntity>> intakes,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final s = S.of(sheetContext);
      final theme = Theme.of(sheetContext);
      final open = <(MealSlot, MealGap, Set<String>)>[];
      for (final slot in slots) {
        final logged = intakes[slot.id] ?? const <IntakeEntity>[];
        final budget = budgets[slot.id];
        if (logged.isEmpty || budget == null) continue;
        final gap = MealGap.of(
          budget: budget,
          used: used[slot.id] ?? MacroPoints.zero,
          fibreTarget: fibreTargets[slot.id] ?? 0,
          fibreUsed: logged.fibrePoints,
        );
        if (gap.isClosed) continue;
        final inMeal = <String>{
          for (final intake in logged)
            ?FoodKnowledge.instance?.match(intake.meal.name ?? '')?.id,
        };
        open.add((slot, gap, inMeal));
      }
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
            Text(s.closerSheetTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: Dimens.spacing4),
            Text(
              open.isEmpty ? s.closerSheetEmpty : s.closerSheetHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final (slot, gap, inMeal) in open) ...[
              const SizedBox(height: Dimens.spacing16),
              Text(
                mealSlotLabel(context, slot),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Dimens.spacing8),
              MealCloserPanel(
                gap: gap,
                excludeConcepts: inMeal,
                onPick: (suggestion) {
                  final navigator = Navigator.of(context);
                  final lang = Localizations.localeOf(context).languageCode;
                  navigator.pop();
                  MealSlotContext.select(slot);
                  navigator.pushNamed(
                    NavigationOptions.mealDetailRoute,
                    arguments: MealDetailScreenArguments(
                      suggestion.food.toMealEntity(lang),
                      slot.baseType,
                      DateTime.now(),
                      false,
                      initialGrams: suggestion.grams,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      );
    },
  );
}
