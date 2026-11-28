import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_warning.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';
import 'package:opennutritracker/features/food_knowledge/presentation/unit_weight_dialog.dart';
import 'package:opennutritracker/features/meal_closer/domain/meal_closer.dart';
import 'package:opennutritracker/features/meal_closer/presentation/meal_closer_panel.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/presentation/dish_picker_screen.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Edits the foods of one planned meal: change amounts, take foods out, and
/// add new ones, from suggestions for what the meal still lacks or by
/// searching. Pops the new list on save, null on cancel.
class PlannedMealEditorScreen extends StatefulWidget {
  /// "Lunch · Mon 28", or "Ann · Lunch · Mon 28" for someone else's menu.
  final String title;
  final DateTime day;
  final IntakeTypeEntity mealType;
  final List<PlannedItem> items;

  /// The meal's points; null when there is no budget to compare against.
  final MacroPoints? budget;

  /// The meal's share of the day's minimum fibre, in fibre points.
  final double fibreTarget;

  /// Whether the meal is already in the diary, which saving updates too.
  final bool logged;

  const PlannedMealEditorScreen({
    super.key,
    required this.title,
    required this.day,
    required this.mealType,
    required this.items,
    this.budget,
    this.fibreTarget = 0,
    this.logged = false,
  });

  @override
  State<PlannedMealEditorScreen> createState() =>
      _PlannedMealEditorScreenState();
}

class _PlannedMealEditorScreenState extends State<PlannedMealEditorScreen> {
  late List<PlannedItem> _items = [...widget.items];
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  MacroPoints get _used =>
      _items.fold(MacroPoints.zero, (sum, i) => sum + i.points);

  double get _fibre => _items.fold(0.0, (sum, i) => sum + i.fibrePoints);

  TextEditingController _controllerFor(PlannedItem item) =>
      _controllers.putIfAbsent(item.id, () {
        final format = PointsFormat.of(context);
        return TextEditingController(text: format.grams(item.amount));
      });

  void _setAmount(PlannedItem item, String text) {
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null || value <= 0) return;
    setState(() {
      _items = [
        for (final i in _items) i.id == item.id ? i.copyWith(amount: value) : i,
      ];
    });
  }

  void _remove(PlannedItem item) => setState(() {
    _items = _items.where((i) => i.id != item.id).toList();
    _controllers.remove(item.id)?.dispose();
  });

  void _add(PlannedItem item) => setState(() => _items = [..._items, item]);

  Future<void> _search() async {
    final budget = widget.budget;
    final item = await Navigator.of(context).push<PlannedItem>(
      MaterialPageRoute(
        builder: (_) => DishPickerScreen(
          day: widget.day,
          mealType: widget.mealType,
          remaining: budget == null ? null : budget - _used,
        ),
      ),
    );
    if (item != null && mounted) _add(item);
  }

  void _addSuggestion(CloserSuggestion c) {
    final meal = closerMeal(context, c);
    _add(
      PlannedItem(
        id: IdGenerator.getUniqueID(),
        meal: meal,
        amount: c.grams.roundToDouble(),
        unit: meal.isLiquid ? 'ml' : 'g',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final format = PointsFormat.of(context);
    final budget = widget.budget;
    final used = _used;
    final over = budget != null && used.total > budget.total + 0.001;
    final gap = budget == null
        ? null
        : MealGap.of(
            budget: budget,
            used: used,
            fibreTarget: widget.fibreTarget,
            fibreUsed: _fibre,
          );
    final lang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Semantics(
            identifier: 'meal-editor-save',
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(_items),
              child: Text(s.mealEditorSave),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Dimens.spacing16),
        children: [
          Text(
            budget == null
                ? '${format.points(used.total)} ${s.pointsShort}'
                : '${format.points(used.total)} / '
                      '${format.points(budget.total)} ${s.pointsShort}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: over ? theme.colorScheme.error : null,
            ),
          ),
          if (widget.logged) ...[
            const SizedBox(height: Dimens.spacing8),
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing12),
                child: Text(s.mealEditorLoggedNote),
              ),
            ),
          ],
          const SizedBox(height: Dimens.spacing8),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
              child: Text(
                s.plannerEmptyMeal,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final item in _items)
            ListTile(
              key: ValueKey(item.id),
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: Dimens.spacing4),
                    child: DietBadge(item.name, code: item.meal.code),
                  ),
                ],
              ),
              subtitle: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Dimens.spacing4,
                children: [
                  Text('${format.points(item.points.total)} ${s.pointsShort}'),
                  // EatPoint: tap to set what one unit of it weighs.
                  Semantics(
                    identifier: 'meal-editor-unit-weight',
                    child: InkWell(
                      borderRadius: Dimens.borderRadiusM,
                      onTap: () async {
                        final changed = await showUnitWeightDialog(
                          context,
                          name: item.name,
                          code: item.meal.code,
                        );
                        if (changed && mounted) setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                switch (PortionFormatter.forFood(
                                  item.name,
                                  item.amount,
                                  code: item.meal.code,
                                )) {
                                  final portion? =>
                                    '· ≈ ${portion.label(lang)}',
                                  null => '· ${s.unitWeightAdd}',
                                },
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.edit_rounded,
                              size: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 72,
                    child: Semantics(
                      identifier: 'meal-editor-amount',
                      child: TextField(
                        controller: _controllerFor(item),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        textAlign: TextAlign.end,
                        decoration: InputDecoration(
                          isDense: true,
                          suffixText: item.unit,
                        ),
                        onChanged: (text) => _setAmount(item, text),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: s.plannerRemoveItem,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _remove(item),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Dimens.spacing8),
          Semantics(
            identifier: 'meal-editor-search',
            child: OutlinedButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.search_rounded),
              label: Text(s.mealEditorSearch),
            ),
          ),
          if (gap != null) ...[
            const SizedBox(height: Dimens.spacing16),
            MealCloserPanel(
              gap: gap,
              excludeConcepts: const {},
              onPick: _addSuggestion,
            ),
          ],
        ],
      ),
    );
  }
}
