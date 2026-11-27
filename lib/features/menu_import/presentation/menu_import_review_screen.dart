import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/menu_import/data/menu_food_matcher.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/menu_import/domain/menu_import_plan.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Shows what was read from an imported menu, matched to foods and with
/// amounts filled in, and writes it into the weekly menu once the user
/// agrees. Every day, meal, food and amount can be changed first.
class MenuImportReviewScreen extends StatefulWidget {
  final ImportedMenu menu;
  final List<MealSlot> slots;
  final DateTime? initialWeek;

  /// For tests: matching without the food databases.
  final MenuFoodMatcher? matcher;

  const MenuImportReviewScreen({
    super.key,
    required this.menu,
    required this.slots,
    this.initialWeek,
    this.matcher,
  });

  @override
  State<MenuImportReviewScreen> createState() => _MenuImportReviewScreenState();
}

class _MenuImportReviewScreenState extends State<MenuImportReviewScreen> {
  late final MenuFoodMatcher _matcher = widget.matcher ?? MenuFoodMatcher();
  final Map<ImportedFood, MatchedFood> _matches = {};
  int _matched = 0;
  bool _matching = true;

  late DateTime _start = _defaultStart();
  bool _fit = true;
  bool _replace = false;
  Map<String, MacroPoints> _budgets = const {};
  List<PlanDay> _plan = const [];

  /// The user's corrections: grams per food and meal per imported meal,
  /// keyed by their position, kept when the plan is rebuilt.
  final Map<String, double> _gramsEdits = {};
  final Map<String, MealSlot> _slotEdits = {};
  final Set<String> _removed = {};

  DateTime _defaultStart() {
    final base = widget.initialWeek ?? DateTime.now();
    final usesWeekdays = widget.menu.days.any((d) => d.weekday != null);
    return usesWeekdays ? DayPlan.weekStart(base) : DayPlan.dateOnly(base);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (locator.isRegistered<GetPointsBudgetUsecase>()) {
      try {
        final budget = await locator<GetPointsBudgetUsecase>().getBudget();
        _budgets = budget.perSlot.isEmpty
            ? widget.slots.budgets(budget.daily)
            : budget.perSlot;
      } catch (_) {}
    }
    final foods = [
      for (final d in widget.menu.days)
        for (final m in d.meals) ...m.foods,
    ];
    // A few at a time: the database search is online.
    const batch = 4;
    for (var i = 0; i < foods.length; i += batch) {
      final chunk = foods.skip(i).take(batch).toList();
      final results = await Future.wait(chunk.map(_matcher.match));
      for (var k = 0; k < chunk.length; k++) {
        _matches[chunk[k]] = results[k];
      }
      if (!mounted) return;
      setState(() => _matched = _matches.length);
    }
    if (!mounted) return;
    setState(() {
      _matching = false;
      _rebuild();
    });
  }

  void _rebuild() {
    final plan = MenuImportPlanner.build(
      menu: widget.menu,
      slots: widget.slots,
      nameOf: (slot) => mealSlotLabel(context, slot),
      start: _start,
      budgets: _budgets,
      fitToBudget: _fit,
      match: (food) {
        final m = _matches[food];
        return (meal: m?.meal, usual: m?.usualAmount);
      },
    );
    // Re-apply the user's corrections.
    _plan = [
      for (var d = 0; d < plan.length; d++)
        PlanDay(
          source: plan[d].source,
          date: plan[d].date,
          meals: [
            for (var m = 0; m < plan[d].meals.length; m++)
              if (!_removed.contains('$d/$m'))
                PlanMeal(
                  source: plan[d].meals[m].source,
                  slot: _slotEdits['$d/$m'] ?? plan[d].meals[m].slot,
                  foods: [
                    for (var f = 0; f < plan[d].meals[m].foods.length; f++)
                      if (!_removed.contains('$d/$m/$f'))
                        _gramsEdits['$d/$m/$f'] != null
                            ? plan[d].meals[m].foods[f].withGrams(
                                _gramsEdits['$d/$m/$f']!,
                              )
                            : plan[d].meals[m].foods[f],
                  ],
                ),
          ],
        ),
    ];
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _start = widget.menu.days.any((d) => d.weekday != null)
          ? DayPlan.weekStart(picked)
          : DayPlan.dateOnly(picked);
      _rebuild();
    });
  }

  Future<void> _editGrams(String key, PlanFood food) async {
    final controller = TextEditingController(
      text: PointsFormat.of(context).grams(food.grams),
    );
    final s = S.of(context);
    final grams = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(food.meal?.name ?? food.source.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: food.meal?.isLiquid == true ? 'ml' : 'g',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.dialogCancelLabel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, PointsFormat.parse(controller.text)),
            child: Text(s.buttonSaveLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (grams == null || grams <= 0 || grams > 5000) return;
    setState(() {
      _gramsEdits[key] = grams;
      _rebuild();
    });
  }

  Future<void> _save() async {
    final planner = locator<PlannerDataSource>();
    var days = 0;
    for (final day in _plan) {
      final next = MenuImportPlanner.toDayPlan(
        day,
        planner.getDay(day.date),
        replace: _replace,
      );
      await planner.saveDay(next);
      days++;
    }
    if (mounted) Navigator.of(context).pop(days);
  }

  int get _unmatched => _plan.fold(
    0,
    (n, d) =>
        n +
        d.meals.fold(
          0,
          (m, meal) => m + meal.foods.where((f) => f.meal == null).length,
        ),
  );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final format = PointsFormat.of(context);
    final total = widget.menu.foodCount;

    return Scaffold(
      appBar: AppBar(title: Text(s.menuImportReviewTitle)),
      body: _matching
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      value: total == 0 ? null : _matched / total,
                    ),
                    const SizedBox(height: Dimens.spacing16),
                    Text(
                      s.menuImportMatching(
                        _matched.toString(),
                        total.toString(),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing16,
                Dimens.spacing8,
                Dimens.spacing16,
                96,
              ),
              children: [
                Text(
                  s.menuImportFound(_plan.length.toString(), total.toString()),
                  style: theme.textTheme.titleMedium,
                ),
                if (_unmatched > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: Dimens.spacing4),
                    child: Text(
                      s.menuImportUnmatched(_unmatched.toString()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: Dimens.spacing8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: Text(s.menuImportStartsOn),
                  subtitle: Text(DateFormat.yMMMMEEEEd(locale).format(_start)),
                  trailing: const Icon(Icons.edit_calendar_rounded),
                  onTap: _pickStart,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.tune_rounded),
                  title: Text(s.menuImportFit),
                  subtitle: Text(s.menuImportFitHelp),
                  value: _fit,
                  onChanged: (v) => setState(() {
                    _fit = v;
                    _rebuild();
                  }),
                ),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(s.menuImportAdd)),
                    ButtonSegment(
                      value: true,
                      label: Text(s.menuImportReplace),
                    ),
                  ],
                  selected: {_replace},
                  onSelectionChanged: (v) => setState(() => _replace = v.first),
                ),
                const SizedBox(height: Dimens.spacing8),
                for (var d = 0; d < _plan.length; d++)
                  _dayCard(context, d, _plan[d], format, locale),
              ],
            ),
      bottomNavigationBar: _matching
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.spacing16,
                  Dimens.spacing8,
                  Dimens.spacing16,
                  Dimens.spacing16,
                ),
                child: Semantics(
                  identifier: 'menu-import-save',
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(Dimens.minTouchTarget),
                    ),
                    onPressed: _plan.isEmpty ? null : _save,
                    icon: const Icon(Icons.playlist_add_check_rounded),
                    label: Text(s.menuImportSave(_plan.length.toString())),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _dayCard(
    BuildContext context,
    int d,
    PlanDay day,
    PointsFormat format,
    String locale,
  ) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: Dimens.spacing12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing12,
          Dimens.spacing8,
          Dimens.spacing8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              toBeginningOfSentenceCase(
                DateFormat.MMMMEEEEd(locale).format(day.date),
              ),
              style: theme.textTheme.titleMedium,
            ),
            // Weekdays and dates are already in the title; "Day 3" is not.
            if (day.source.label != null &&
                day.source.weekday == null &&
                day.source.date == null)
              Text(
                s.menuImportReadAs(day.source.label!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            for (var m = 0; m < day.meals.length; m++)
              _mealBlock(context, '$d/$m', day.meals[m], format),
          ],
        ),
      ),
    );
  }

  Widget _mealBlock(
    BuildContext context,
    String key,
    PlanMeal meal,
    PointsFormat format,
  ) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final budget = _budgets[meal.slot.id];
    return Padding(
      padding: const EdgeInsets.only(top: Dimens.spacing8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(mealSlotIcon(meal.slot), size: 18),
              const SizedBox(width: Dimens.spacing8),
              PopupMenuButton<MealSlot>(
                tooltip: s.menuImportChangeMeal,
                onSelected: (slot) => setState(() {
                  _slotEdits[key] = slot;
                  _rebuild();
                }),
                itemBuilder: (context) => [
                  for (final slot in widget.slots)
                    PopupMenuItem(
                      value: slot,
                      child: Text(mealSlotLabel(context, slot)),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      mealSlotLabel(context, meal.slot),
                      style: theme.textTheme.titleSmall,
                    ),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                budget == null
                    ? '${format.points(meal.points.total)} ${s.pointsShort}'
                    : '${format.points(meal.points.total)} / '
                          '${format.points(budget.total)} ${s.pointsShort}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                tooltip: s.plannerRemoveItem,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() {
                  _removed.add(key);
                  _rebuild();
                }),
              ),
            ],
          ),
          if (meal.source.label != null &&
              MenuTextParserLabel.differs(
                meal.source.label!,
                mealSlotLabel(context, meal.slot),
              ))
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                s.menuImportReadAs(meal.source.label!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (var f = 0; f < meal.foods.length; f++)
            _foodRow(context, '$key/$f', meal.foods[f], format),
        ],
      ),
    );
  }

  Widget _foodRow(
    BuildContext context,
    String key,
    PlanFood food,
    PointsFormat format,
  ) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final match = _matches[food.source];
    final origin = match?.origin ?? MatchOrigin.none;
    final unit = food.meal?.isLiquid == true ? 'ml' : 'g';
    final (icon, tooltip) = switch (origin) {
      MatchOrigin.mine => (
        Icons.person_outline_rounded,
        s.menuImportOriginMine,
      ),
      MatchOrigin.database => (
        Icons.storage_rounded,
        s.menuImportOriginDatabase,
      ),
      MatchOrigin.estimate => (
        Icons.auto_awesome_outlined,
        s.menuImportOriginEstimate,
      ),
      MatchOrigin.none => (Icons.help_outline_rounded, s.menuImportOriginNone),
    };
    final amountNote = switch (food.amountSource) {
      AmountSource.fitted => s.menuImportAmountFitted,
      AmountSource.fromPoints => s.menuImportAmountFromPoints,
      AmountSource.usual => s.menuImportAmountUsual,
      _ => null,
    };
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 26),
      dense: true,
      leading: Tooltip(
        message: tooltip,
        child: Icon(
          icon,
          size: 18,
          color: origin == MatchOrigin.none
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      minLeadingWidth: 20,
      title: Text(
        food.meal?.name ?? food.source.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (food.meal == null)
            s.menuImportNotFound(food.source.name)
          else ...[
            '${format.grams(food.grams)} $unit · '
                '${format.points(food.points.total)} ${s.pointsShort}',
            ?amountNote,
          ],
        ].join(' · '),
      ),
      onTap: food.meal == null ? null : () => _editGrams(key, food),
      trailing: IconButton(
        tooltip: s.plannerRemoveItem,
        icon: const Icon(Icons.close_rounded, size: 18),
        onPressed: () => setState(() {
          _removed.add(key);
          _rebuild();
        }),
      ),
    );
  }
}

/// Whether a meal label as read differs from the user's meal it went to.
class MenuTextParserLabel {
  MenuTextParserLabel._();

  static bool differs(String read, String meal) =>
      read.trim().toLowerCase() != meal.trim().toLowerCase();
}
