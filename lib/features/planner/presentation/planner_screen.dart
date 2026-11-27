import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';
import 'package:opennutritracker/features/insights/presentation/week_insights_card.dart';
import 'package:opennutritracker/features/menu_import/presentation/menu_import_screen.dart';
import 'package:opennutritracker/features/planner/data/planned_meal_logger.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/data/planner_reminder_service.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/domain/shopping_list_builder.dart';
import 'package:opennutritracker/features/planner/presentation/dish_picker_screen.dart';
import 'package:opennutritracker/features/planner/presentation/planned_meal_editor_screen.dart';
import 'package:opennutritracker/features/planner/presentation/planner_reminders_screen.dart';
import 'package:opennutritracker/features/planner/presentation/shopping_list_screen.dart';
import 'package:opennutritracker/features/planner/presentation/planner_calendar_screen.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_auto_sync.dart';
import 'package:opennutritracker/features/sync/presentation/member_avatar.dart';
import 'package:opennutritracker/features/sync/presentation/member_day_screen.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/features/travel/presentation/travel_mode_banner.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_warning.dart';
import 'package:opennutritracker/features/menu_generator/presentation/menu_generator_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:share_plus/share_plus.dart';

/// The weekly menu: a day strip, each meal's planned dishes with their
/// points against the meal budget, logging a planned meal in one tap, and
/// the week's shopping list.
class PlannerScreen extends StatefulWidget {
  final DateTime? initialDay;

  const PlannerScreen({super.key, this.initialDay});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

enum _DayAction {
  generateMenu,
  importMenu,
  copyPreviousWeek,
  copyDayTo,
  clearDay,
  shareWeek,
  reminders,
}

class _PlannerScreenState extends State<PlannerScreen> {
  final _source = locator<PlannerDataSource>();
  late DateTime _selected = DayPlan.dateOnly(
    widget.initialDay ?? DateTime.now(),
  );
  List<DayPlan> _week = const [];
  PointsBudgetResult? _budget;
  final Set<String> _logging = {};

  /// The user's meals, in the order of a day.
  List<MealSlot> get _slots => _budget?.slots.isNotEmpty == true
      ? _budget!.slots
      : MealSlot.builtIn();

  /// The user's meals plus, for the selected day, any meal planned earlier
  /// that the user has since removed, so its food stays visible.
  List<MealSlot> _slotsFor(DayPlan day) => [
    ..._slots,
    for (final id in day.meals.keys)
      if (_slots.byId(id) == null && day.itemsFor(id).isNotEmpty)
        MealSlot(
          id: id,
          baseType: MealSlot.dayOrder
                  .where((t) => t.name == id)
                  .firstOrNull ??
              MealSlot.dayOrder.last,
          share: MacroPoints.zero,
        ),
  ];

  DateTime get _weekStart => DayPlan.weekStart(_selected);

  /// EatPoint household: the other members' menus, shown read-only.
  final HouseholdStore? _household = locator.isRegistered<HouseholdStore>()
      ? locator<HouseholdStore>()
      : null;
  List<MemberSnapshot> _others = const [];
  bool _viewBoth = true;

  @override
  void initState() {
    super.initState();
    _source.revision.addListener(_reload);
    _household?.revision.addListener(_reload);
    HouseholdAutoSync.instance.attach();
    _reload();
    _loadBudget();
  }

  @override
  void dispose() {
    _source.revision.removeListener(_reload);
    _household?.revision.removeListener(_reload);
    HouseholdAutoSync.instance.detach();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _week = _source.getWeek(_selected);
      _others = _household?.getHousehold() == null
          ? const []
          : _household!.otherMembers();
    });
  }

  Future<void> _copyToMine(MealSlot slot, PlannedItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = S.of(context).plannerCopied;
    final day = _day;
    await _save(
      day.withMeal(slot.id, [
        ...day.itemsFor(slot.id),
        PlannedItem(
          id: IdGenerator.getUniqueID(),
          meal: item.meal,
          amount: item.amount,
          unit: item.unit,
        ),
      ]),
    );
    messenger.showSnackBar(SnackBar(content: Text(copied)));
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
    if (TravelModeGate.remindersPaused) return;
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
      slots: _slots,
      upcoming: [
        for (var i = 0; i < 7; i++)
          _source.getDay(today.add(Duration(days: i))),
      ],
      texts: plannerReminderTextsOf(context),
    );
  }

  Future<void> _openCalendar() async {
    final picked = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (_) => PlannerCalendarScreen(initialDay: _selected),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selected = DayPlan.dateOnly(picked));
    _reload();
  }

  void _moveWeek(int weeks) {
    setState(() => _selected = _selected.add(Duration(days: 7 * weeks)));
    _reload();
  }

  Future<void> _addDish(MealSlot slot) async {
    final budget = _budget?.perSlot[slot.id];
    final remaining = budget == null
        ? null
        : budget - _day.pointsFor(slot.id);
    final item = await Navigator.of(context).push<PlannedItem>(
      MaterialPageRoute(
        builder: (_) => DishPickerScreen(
          day: _selected,
          mealType: slot.baseType,
          remaining: remaining,
        ),
      ),
    );
    if (item == null) return;
    final day = _day;
    await _save(day.withMeal(slot.id, [...day.itemsFor(slot.id), item]));
  }

  Future<void> _removeItem(MealSlot slot, PlannedItem item) async {
    final day = _day;
    await _save(
      day.withMeal(
        slot.id,
        day.itemsFor(slot.id).where((i) => i.id != item.id).toList(),
      ),
    );
  }

  /// Logs every food planned for [slot] on the selected day, the same way
  /// the amount sheet logs one, into that meal of the diary.
  Future<void> _logMeal(MealSlot slot) async {
    final day = _day;
    final items = day.itemsFor(slot.id);
    if (items.isEmpty || _logging.contains(slot.id)) return;
    setState(() => _logging.add(slot.id));
    final bloc = locator<MealDetailBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final mealName = mealSlotLabel(context, slot);
    try {
      final logged = await PlannedMealLogger.app(context).log(
        day,
        slot,
        PlannedMealLogger.appAdd(context, bloc, slot, day.date),
      );
      await _save(logged);
      PlannedMealLogger.refreshDiary();
      messenger.showSnackBar(
        SnackBar(content: Text(s.plannerLoggedSnack(mealName))),
      );
    } finally {
      await bloc.close();
      if (mounted) setState(() => _logging.remove(slot.id));
    }
  }

  /// EatPoint: changes a day's meal (amounts, foods out, foods in). A meal
  /// already logged is taken out of the diary and logged again as edited.
  Future<void> _editMeal(MealSlot slot) async {
    final day = _day;
    final locale = Localizations.localeOf(context).toString();
    final wasLogged = day.logged.contains(slot.id);
    final edited = await Navigator.of(context).push<List<PlannedItem>>(
      MaterialPageRoute(
        builder: (_) => PlannedMealEditorScreen(
          title:
              '${mealSlotLabel(context, slot)} · '
              '${DateFormat.MMMEd(locale).format(day.date)}',
          day: day.date,
          mealType: slot.baseType,
          items: day.itemsFor(slot.id),
          budget: _budget?.perSlot[slot.id],
          fibreTarget: _budget?.fibrePerSlot[slot.id] ?? 0,
          logged: wasLogged,
        ),
      ),
    );
    if (edited == null || !mounted) return;
    if (!wasLogged) {
      await _save(_day.withMeal(slot.id, edited));
      return;
    }
    setState(() => _logging.add(slot.id));
    final bloc = locator<MealDetailBloc>();
    try {
      final logger = PlannedMealLogger.app(context);
      var next = (await logger.unlog(_day, slot)).withMeal(slot.id, edited);
      if (edited.isNotEmpty && mounted) {
        next = await logger.log(
          next,
          slot,
          PlannedMealLogger.appAdd(context, bloc, slot, next.date),
        );
      }
      await _save(next);
      PlannedMealLogger.refreshDiary();
    } finally {
      await bloc.close();
      if (mounted) setState(() => _logging.remove(slot.id));
    }
  }

  /// EatPoint: takes a meal logged by mistake back out of the diary.
  Future<void> _unlogMeal(MealSlot slot) async {
    final s = S.of(context);
    final mealName = mealSlotLabel(context, slot);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.plannerUnlogTitle(mealName)),
        content: Text(s.plannerUnlogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.plannerUnlog),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _logging.add(slot.id));
    try {
      await _save(await PlannedMealLogger.app(context).unlog(_day, slot));
      PlannedMealLogger.refreshDiary();
      messenger.showSnackBar(
        SnackBar(content: Text(s.plannerUnloggedSnack(mealName))),
      );
    } finally {
      if (mounted) setState(() => _logging.remove(slot.id));
    }
  }

  Future<void> _onAction(_DayAction action) async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case _DayAction.generateMenu:
        final days = await Navigator.of(context).push<int>(
          MaterialPageRoute(
            builder: (_) => MenuGeneratorScreen(initialDay: _weekStart),
          ),
        );
        if (days != null && days > 0) {
          await _rescheduleReminders();
          messenger.showSnackBar(
            SnackBar(content: Text(s.generatorDone(days.toString()))),
          );
        }
      case _DayAction.importMenu:
        final days = await Navigator.of(context).push<int>(
          MaterialPageRoute(
            builder: (_) => MenuImportScreen(initialWeek: _selected),
          ),
        );
        if (days != null && days > 0) {
          await _rescheduleReminders();
          messenger.showSnackBar(
            SnackBar(content: Text(s.menuImportDone(days.toString()))),
          );
        }
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
      case _DayAction.shareWeek:
        await _shareWeek();
      case _DayAction.reminders:
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PlannerRemindersScreen()),
        );
    }
  }

  /// Shares the week's menu as plain text.
  Future<void> _shareWeek() async {
    final s = S.of(context);
    final locale = Localizations.localeOf(context).toString();
    final format = PointsFormat.of(context);
    final buffer = StringBuffer('${s.plannerTitle}\n');
    for (final day in _week) {
      if (day.isEmpty) continue;
      buffer.writeln();
      buffer.writeln(DateFormat.MMMMEEEEd(locale).format(day.date));
      for (final slot in _slotsFor(day)) {
        final items = day.itemsFor(slot.id);
        if (items.isEmpty) continue;
        buffer.writeln(
          '  ${_slotName(context, slot)} · '
          '${format.points(day.pointsFor(slot.id).total)} ${s.pointsShort}',
        );
        for (final item in items) {
          buffer.writeln(
            '    - ${item.name} (${format.grams(item.amount)} ${item.unit})',
          );
        }
      }
    }
    await SharePlus.instance.share(ShareParams(text: buffer.toString()));
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
            identifier: 'planner-calendar',
            child: IconButton(
              tooltip: s.plannerCalendarTitle,
              onPressed: _openCalendar,
              icon: const Icon(Icons.calendar_month_rounded),
            ),
          ),
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
                  value: _DayAction.generateMenu,
                  child: Text(s.generatorTitle),
                ),
                PopupMenuItem(
                  value: _DayAction.importMenu,
                  child: Text(s.menuImportTitle),
                ),
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
                  value: _DayAction.shareWeek,
                  child: Text(s.plannerShareWeek),
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
          if (TravelModeGate.plannerPaused) const TravelModeBanner(),
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
                if (_others.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Dimens.spacing8),
                    child: Semantics(
                      identifier: 'planner-view-toggle',
                      child: SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(s.plannerViewMine),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(s.plannerViewBoth),
                          ),
                        ],
                        selected: {_viewBoth},
                        onSelectionChanged: (v) =>
                            setState(() => _viewBoth = v.first),
                      ),
                    ),
                  ),
                WeekInsightsCard(
                  week: _week,
                  fibreTargetPoints: budget?.fibreDaily ?? 5,
                ),
                if (budget != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: Dimens.spacing8,
                    ),
                    child: Text(
                      [
                        s.plannerDayPoints(
                          format.points(day.totalPoints.total),
                          format.points(budget.daily.total),
                        ),
                        if (budget.fibreDaily > 0)
                          s.plannerDayFibre(
                            format.points(day.totalFibre),
                            format.points(budget.fibreDaily),
                          ),
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                for (final slot in _slotsFor(day))
                  _mealCard(context, day, slot),
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
                final allLogged = plan.fullyLogged;
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
                            : scheme.primary.withValues(alpha: 0.14),
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

  /// A meal's name; a meal the user has since removed shows as "Other".
  String _slotName(BuildContext context, MealSlot slot) =>
      _slots.byId(slot.id) != null || slot.id == slot.baseType.name
      ? mealSlotLabel(context, slot)
      : S.of(context).plannerOtherMeal;

  Widget _mealCard(BuildContext context, DayPlan day, MealSlot slot) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final format = PointsFormat.of(context);
    final items = day.itemsFor(slot.id);
    final points = day.pointsFor(slot.id);
    final mealBudget = _budget?.perSlot[slot.id];
    final logged = day.logged.contains(slot.id);
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
                Icon(mealSlotIcon(slot), size: 20),
                const SizedBox(width: Dimens.spacing8),
                Expanded(
                  child: Text(
                    _slotName(context, slot),
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
                Semantics(
                  identifier: 'planner-edit-${slot.id}',
                  child: IconButton(
                    tooltip: s.mealEditorTitle,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _logging.contains(slot.id)
                        ? null
                        : () => _editMeal(slot),
                  ),
                ),
                if (logged)
                  Semantics(
                    identifier: 'planner-unlog-${slot.id}',
                    child: ActionChip(
                      avatar: const Icon(Icons.check_rounded, size: 16),
                      label: Text(s.plannerLogged),
                      tooltip: s.plannerUnlog,
                      visualDensity: VisualDensity.compact,
                      onPressed: _logging.contains(slot.id)
                          ? null
                          : () => _unlogMeal(slot),
                    ),
                  )
                else if (items.isNotEmpty)
                  Semantics(
                    identifier: 'planner-log-${slot.id}',
                    child: OutlinedButton(
                      onPressed: _logging.contains(slot.id)
                          ? null
                          : () => _logMeal(slot),
                      child: _logging.contains(slot.id)
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
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: Dimens.spacing4),
                      child: DietBadge(item.name, code: item.meal.code),
                    ),
                  ],
                ),
                subtitle: Row(
                  children: [
                    Flexible(
                      child: Text(
                        [
                          '${format.grams(item.amount)} ${item.unit}',
                          if (PortionFormatter.forFood(item.name, item.amount)
                              case final portion?)
                            '≈ ${portion.label(Localizations.localeOf(context).languageCode)}',
                          '${format.points(item.points.total)} ${s.pointsShort}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                        onPressed: () => _removeItem(slot, item),
                      ),
              ),
            if (_viewBoth)
              for (final member in _others)
                for (final other
                    in member.dayFor(day.date)?.itemsFor(slot.id) ??
                        const <PlannedItem>[])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MemberDayScreen(
                          memberId: member.memberId,
                          date: day.date,
                        ),
                      ),
                    ),
                    leading: MemberAvatar(
                      name: member.name,
                      colourKey: member.memberId,
                    ),
                    title: Text(
                      other.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      items.any(
                            (mine) =>
                                ShoppingListBuilder.normalise(mine.name) ==
                                ShoppingListBuilder.normalise(other.name),
                          )
                          ? s.plannerSameDish(format.points(other.points.total))
                          : '${member.name} · '
                                '${format.grams(other.amount)} ${other.unit} · '
                                '${format.points(other.points.total)} '
                                '${s.pointsShort}',
                    ),
                    trailing: logged
                        ? null
                        : IconButton(
                            tooltip: s.plannerCopyToMine,
                            icon: const Icon(Icons.content_copy_rounded),
                            onPressed: () => _copyToMine(slot, other),
                          ),
                  ),
            if (!logged)
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  identifier: 'planner-add-${slot.id}',
                  child: TextButton.icon(
                    onPressed: () => _addDish(slot),
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
