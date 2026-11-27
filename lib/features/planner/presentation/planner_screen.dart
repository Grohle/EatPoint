import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/data/planner_reminder_service.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/domain/shopping_list_builder.dart';
import 'package:opennutritracker/features/planner/presentation/dish_picker_screen.dart';
import 'package:opennutritracker/features/planner/presentation/planner_reminders_screen.dart';
import 'package:opennutritracker/features/planner/presentation/shopping_list_screen.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The weekly menu: a day strip, each meal's planned dishes with their
/// points against the meal budget, logging a planned meal in one tap, and
/// the week's shopping list.
class PlannerScreen extends StatefulWidget {
  final DateTime? initialDay;

  const PlannerScreen({super.key, this.initialDay});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

enum _DayAction { copyPreviousWeek, copyDayTo, clearDay, reminders }

class _PlannerScreenState extends State<PlannerScreen> {
  final _source = locator<PlannerDataSource>();
  late DateTime _selected = DayPlan.dateOnly(
    widget.initialDay ?? DateTime.now(),
  );
  List<DayPlan> _week = const [];
  PointsBudgetResult? _budget;
  final Set<IntakeTypeEntity> _logging = {};

  DateTime get _weekStart => DayPlan.weekStart(_selected);

  @override
  void initState() {
    super.initState();
    _source.revision.addListener(_reload);
    _reload();
    _loadBudget();
  }

  @override
  void dispose() {
    _source.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _week = _source.getWeek(_selected));
  }

  Future<void> _loadBudget() async {
    try {
      final budget = await locator<GetPointsBudgetUsecase>().getBudget();
      if (mounted) setState(() => _budget = budget);
    } catch (_) {}
  }

  DayPlan get _day => _week.firstWhere(
    (d) => d.date == _selected,
    orElse: () => DayPlan.empty(_selected),
  );

  Future<void> _save(DayPlan plan) async {
    await _source.saveDay(plan);
    await _rescheduleReminders();
  }

  Future<void> _rescheduleReminders() async {
    final settings = _source.getReminders();
    if (settings.planWeek == null &&
        settings.shopping == null &&
        settings.prepare == null &&
        settings.logAfterMinutes == null) {
      return;
    }
    if (!mounted) return;
    final today = DayPlan.dateOnly(DateTime.now());
    await locator<PlannerReminderService>().reschedule(
      settings: settings,
      upcoming: [
        for (var i = 0; i < 7; i++)
          _source.getDay(today.add(Duration(days: i))),
      ],
      texts: plannerReminderTextsOf(context),
    );
  }

  void _moveWeek(int weeks) {
    setState(() => _selected = _selected.add(Duration(days: 7 * weeks)));
    _reload();
  }

  Future<void> _addDish(IntakeTypeEntity type) async {
    final budget = _budget?.perMeal[type];
    final remaining = budget == null ? null : budget - _day.pointsFor(type);
    final item = await Navigator.of(context).push<PlannedItem>(
      MaterialPageRoute(
        builder: (_) => DishPickerScreen(
          day: _selected,
          mealType: type,
          remaining: remaining,
        ),
      ),
    );
    if (item == null) return;
    final day = _day;
    await _save(day.withMeal(type, [...day.itemsFor(type), item]));
  }

  Future<void> _removeItem(IntakeTypeEntity type, PlannedItem item) async {
    final day = _day;
    await _save(
      day.withMeal(
        type,
        day.itemsFor(type).where((i) => i.id != item.id).toList(),
      ),
    );
  }

  /// Logs every food planned for [type] on the selected day, the same way
  /// the amount sheet logs one.
  Future<void> _logMeal(IntakeTypeEntity type) async {
    final day = _day;
    final items = day.itemsFor(type);
    if (items.isEmpty || _logging.contains(type)) return;
    setState(() => _logging.add(type));
    final bloc = locator<MealDetailBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final mealName = mealTypeLabel(context, type);
    try {
      for (final item in items) {
        await bloc.addIntake(
          context,
          item.unit,
          item.amount.toString(),
          type,
          item.meal,
          day.date,
        );
      }
      await _save(day.withLogged(type, true));
      locator<HomeBloc>().add(const LoadItemsEvent());
      locator<DiaryBloc>().add(const LoadDiaryYearEvent());
      locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
      messenger.showSnackBar(
        SnackBar(content: Text(s.plannerLoggedSnack(mealName))),
      );
    } finally {
      await bloc.close();
      if (mounted) setState(() => _logging.remove(type));
    }
  }

  Future<void> _onAction(_DayAction action) async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _DayAction.copyPreviousWeek:
        final copied = await _source.copyPreviousWeek(_weekStart);
        await _rescheduleReminders();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              copied == 0
                  ? s.plannerNothingToCopy
                  : s.plannerCopiedDays(copied.toString()),
            ),
          ),
        );
      case _DayAction.copyDayTo:
        await _copyDayTo();
      case _DayAction.clearDay:
        await _save(DayPlan.empty(_selected));
      case _DayAction.reminders:
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PlannerRemindersScreen()),
        );
    }
  }

  Future<void> _copyDayTo() async {
    final source = _day;
    if (source.isEmpty) return;
    final format = DateFormat.E(Localizations.localeOf(context).toString());
    final days = [for (var i = 0; i < 7; i++) _weekStart.add(Duration(days: i))]
      ..removeWhere((d) => d == _selected);
    final chosen = await showDialog<Set<DateTime>>(
      context: context,
      builder: (context) {
        final picked = <DateTime>{};
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(S.of(context).plannerCopyDayTo),
            content: Wrap(
              spacing: Dimens.spacing8,
              children: [
                for (final d in days)
                  FilterChip(
                    label: Text('${format.format(d)} ${d.day}'),
                    selected: picked.contains(d),
                    onSelected: (v) => setDialogState(
                      () => v ? picked.add(d) : picked.remove(d),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  MaterialLocalizations.of(context).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, picked),
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null) return;
    for (final d in chosen) {
      await _source.saveDay(source.copyTo(d));
    }
    await _rescheduleReminders();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context).toString();
    final range =
        '${DateFormat.MMMd(locale).format(_weekStart)} – '
        '${DateFormat.MMMd(locale).format(_weekStart.add(const Duration(days: 6)))}';
    final day = _day;
    final format = PointsFormat.of(context);
    final budget = _budget;
    final shoppingCount = ShoppingListBuilder.build([
      for (final d in _week) (owner: 'me', plan: d),
    ]).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.plannerTitle),
            Text(range, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          Semantics(
            identifier: 'planner-previous-week',
            child: IconButton(
              tooltip: s.plannerPreviousWeek,
              onPressed: () => _moveWeek(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ),
          Semantics(
            identifier: 'planner-next-week',
            child: IconButton(
              tooltip: s.plannerNextWeek,
              onPressed: () => _moveWeek(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          Semantics(
            identifier: 'planner-menu',
            child: PopupMenuButton<_DayAction>(
              onSelected: _onAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _DayAction.copyPreviousWeek,
                  child: Text(s.plannerCopyPreviousWeek),
                ),
                PopupMenuItem(
                  value: _DayAction.copyDayTo,
                  enabled: !day.isEmpty,
                  child: Text(s.plannerCopyDayTo),
                ),
                PopupMenuItem(
                  value: _DayAction.clearDay,
                  enabled: !day.isEmpty,
                  child: Text(s.plannerClearDay),
                ),
                PopupMenuItem(
                  value: _DayAction.reminders,
                  child: Text(s.plannerReminders),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _dayStrip(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing16,
                0,
                Dimens.spacing16,
                Dimens.spacing16,
              ),
              children: [
                if (budget != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: Dimens.spacing8,
                    ),
                    child: Text(
                      s.plannerDayPoints(
                        format.points(day.totalPoints.total),
                        format.points(budget.daily.total),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                for (final type in const [
                  IntakeTypeEntity.breakfast,
                  IntakeTypeEntity.lunch,
                  IntakeTypeEntity.snack,
                  IntakeTypeEntity.dinner,
                ])
                  _mealCard(context, day, type),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing16,
                Dimens.spacing8,
                Dimens.spacing16,
                Dimens.spacing16,
              ),
              child: SizedBox(
                width: double.infinity,
                child: Semantics(
                  identifier: 'planner-shopping-list',
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(Dimens.minTouchTarget),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ShoppingListScreen(weekOf: _weekStart),
                      ),
                    ),
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: Text(
                      s.plannerShoppingButton(shoppingCount.toString()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayStrip(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing12,
        Dimens.spacing8,
        Dimens.spacing12,
        Dimens.spacing4,
      ),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (context) {
                final date = _weekStart.add(Duration(days: i));
                final plan = _week.length > i ? _week[i] : DayPlan.empty(date);
                final selected = date == _selected;
                final allLogged =
                    !plan.isEmpty &&
                    plan.meals.entries
                        .where((e) => e.value.isNotEmpty)
                        .every((e) => plan.logged.contains(e.key));
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Semantics(
                      identifier: 'planner-day-$i',
                      selected: selected,
                      button: true,
                      label: DateFormat.MMMMEEEEd(locale).format(date),
                      excludeSemantics: true,
                      child: Material(
                        color: selected
                            ? scheme.primary
                            : plan.isEmpty
                            ? scheme.surfaceContainerHighest
                            : scheme.primaryContainer,
                        borderRadius: Dimens.borderRadiusM,
                        child: InkWell(
                          borderRadius: Dimens.borderRadiusM,
                          onTap: () => setState(() => _selected = date),
                          child: SizedBox(
                            height: 62,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat.E(
                                    locale,
                                  ).format(date).substring(0, 1).toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: selected
                                        ? scheme.onPrimary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? scheme.onPrimary
                                        : scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: plan.isEmpty
                                        ? Colors.transparent
                                        : allLogged
                                        ? (selected
                                              ? scheme.onPrimary
                                              : scheme.primary)
                                        : const Color(0xFFFFB300),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _mealCard(BuildContext context, DayPlan day, IntakeTypeEntity type) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final format = PointsFormat.of(context);
    final items = day.itemsFor(type);
    final points = day.pointsFor(type);
    final mealBudget = _budget?.perMeal[type];
    final logged = day.logged.contains(type);
    final over = mealBudget != null && points.total > mealBudget.total + 0.001;
    return Card(
      margin: const EdgeInsets.only(bottom: Dimens.spacing12),
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
            Row(
              children: [
                Icon(type.getIconData(), size: 20),
                const SizedBox(width: Dimens.spacing8),
                Expanded(
                  child: Text(
                    mealTypeLabel(context, type),
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  mealBudget == null
                      ? '${format.points(points.total)} ${s.pointsShort}'
                      : '${format.points(points.total)} / '
                            '${format.points(mealBudget.total)} ${s.pointsShort}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: over ? theme.colorScheme.error : null,
                  ),
                ),
                const SizedBox(width: Dimens.spacing8),
                if (logged)
                  Chip(
                    avatar: const Icon(Icons.check_rounded, size: 16),
                    label: Text(s.plannerLogged),
                    visualDensity: VisualDensity.compact,
                  )
                else if (items.isNotEmpty)
                  Semantics(
                    identifier: 'planner-log-${type.name}',
                    child: OutlinedButton(
                      onPressed: _logging.contains(type)
                          ? null
                          : () => _logMeal(type),
                      child: _logging.contains(type)
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(s.plannerLogMeal),
                    ),
                  ),
              ],
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
                child: Text(
                  s.plannerEmptyMeal,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Row(
                  children: [
                    Text(
                      '${format.grams(item.amount)} ${item.unit} · '
                      '${format.points(item.points.total)} ${s.pointsShort}',
                    ),
                    const SizedBox(width: Dimens.spacing8),
                    _MiniSplit(
                      points: item.points,
                      carbs: palette.carbs,
                      protein: palette.protein,
                      fat: palette.fat,
                    ),
                  ],
                ),
                trailing: logged
                    ? null
                    : IconButton(
                        tooltip: s.plannerRemoveItem,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => _removeItem(type, item),
                      ),
              ),
            if (!logged)
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  identifier: 'planner-add-${type.name}',
                  child: TextButton.icon(
                    onPressed: () => _addDish(type),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(s.plannerAddDish),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniSplit extends StatelessWidget {
  final MacroPoints points;
  final Color carbs;
  final Color protein;
  final Color fat;

  const _MiniSplit({
    required this.points,
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  @override
  Widget build(BuildContext context) {
    final total = points.total;
    if (total <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: 44,
        height: 6,
        child: Row(
          children: [
            if (points.carbs > 0)
              Expanded(
                flex: (points.carbs / total * 100).round().clamp(1, 100),
                child: ColoredBox(color: carbs),
              ),
            if (points.protein > 0)
              Expanded(
                flex: (points.protein / total * 100).round().clamp(1, 100),
                child: ColoredBox(color: protein),
              ),
            if (points.fat > 0)
              Expanded(
                flex: (points.fat / total * 100).round().clamp(1, 100),
                child: ColoredBox(color: fat),
              ),
          ],
        ),
      ),
    );
  }
}
