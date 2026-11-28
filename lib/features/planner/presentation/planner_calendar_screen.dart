import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/menu_generator/presentation/menu_generator_screen.dart';
import 'package:opennutritracker/features/menu_import/presentation/menu_import_screen.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_auto_sync.dart';
import 'package:opennutritracker/features/sync/domain/household_menu.dart';
import 'package:opennutritracker/features/sync/presentation/member_avatar.dart';
import 'package:opennutritracker/features/sync/presentation/member_day_screen.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Where the calendar sends the weekly menu: a day and, when a meal was
/// tapped, whose menu and which meal to show.
class PlannerCalendarPick {
  final DateTime date;

  /// The member whose meal was tapped; null for the user's own.
  final String? memberId;
  final String? slotId;

  const PlannerCalendarPick(this.date, {this.memberId, this.slotId});
}

/// A month view of the menu: every day shows how much of the daily budget
/// is planned and whether it was logged, with a dot per member who has a
/// menu that day. Tapping a day slides up everyone's meals; a long press
/// starts choosing several days, to delete, plan, copy or travel.
class PlannerCalendarScreen extends StatefulWidget {
  final DateTime initialDay;

  const PlannerCalendarScreen({super.key, required this.initialDay});

  @override
  State<PlannerCalendarScreen> createState() => _PlannerCalendarScreenState();
}

class _PlannerCalendarScreenState extends State<PlannerCalendarScreen> {
  static const _firstPage = 1200; // months either side of today

  final _source = locator<PlannerDataSource>();
  late final DateTime _origin = DateTime(
    widget.initialDay.year,
    widget.initialDay.month,
  );
  late final PageController _pages = PageController(initialPage: _firstPage);
  late DateTime _month = _origin;
  late DateTime _selected = DayPlan.dateOnly(widget.initialDay);
  PointsBudgetResult? _budget;

  /// EatPoint: the days chosen with a long press.
  final Set<DateTime> _picked = {};

  List<MealSlot> get _mySlots =>
      _budget?.slots.isNotEmpty == true ? _budget!.slots : MealSlot.builtIn();

  /// EatPoint: the household's other members, to show their menus too.
  final HouseholdStore? _household = locator.isRegistered<HouseholdStore>()
      ? locator<HouseholdStore>()
      : null;
  List<MemberSnapshot> get _others => _household?.getHousehold() == null
      ? const []
      : _household!.otherMembers();

  @override
  void initState() {
    super.initState();
    _source.revision.addListener(_refresh);
    _household?.revision.addListener(_refresh);
    _loadBudget();
  }

  @override
  void dispose() {
    _source.revision.removeListener(_refresh);
    _household?.revision.removeListener(_refresh);
    _pages.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBudget() async {
    if (!locator.isRegistered<GetPointsBudgetUsecase>()) return;
    try {
      final budget = await locator<GetPointsBudgetUsecase>().getBudget();
      if (mounted) setState(() => _budget = budget);
    } catch (_) {}
  }

  DateTime _monthAt(int page) =>
      DateTime(_origin.year, _origin.month + page - _firstPage);

  void _goToMonth(int delta) => _pages.animateToPage(
    (_pages.page ?? _firstPage.toDouble()).round() + delta,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOutCubic,
  );

  void _goToToday() {
    final today = DayPlan.dateOnly(DateTime.now());
    final page =
        _firstPage +
        (today.year - _origin.year) * 12 +
        (today.month - _origin.month);
    setState(() => _selected = today);
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context).toString();
    final theme = Theme.of(context);
    final title = toBeginningOfSentenceCase(
      DateFormat.yMMMM(locale).format(_month),
    );

    final selecting = _picked.isNotEmpty;
    return PopScope(
      // Back first leaves choosing days.
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_picked.clear);
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(_picked.clear),
                ),
                title: Text(s.calendarSelectedDays('${_picked.length}')),
              )
            : AppBar(
                title: Text(s.plannerCalendarTitle),
                actions: [
                  TextButton(
                    onPressed: _goToToday,
                    child: Text(s.plannerCalendarToday),
                  ),
                ],
              ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).previousMonthTooltip,
                    onPressed: () => _goToMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          s.plannerCalendarPlannedDays(
                            _plannedDays(_month).toString(),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
                    onPressed: () => _goToMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
            _weekdayHeader(context),
            SizedBox(
              height: 6 * 64.0,
              child: PageView.builder(
                controller: _pages,
                onPageChanged: (page) =>
                    setState(() => _month = _monthAt(page)),
                itemBuilder: (context, page) =>
                    _monthGrid(context, _monthAt(page)),
              ),
            ),
            _legend(context),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing16),
                child: Text(
                  s.calendarHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (selecting) _selectionBar(context),
          ],
        ),
      ),
    );
  }

  int _plannedDays(DateTime month) {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    var count = 0;
    for (var d = 1; d <= days; d++) {
      if (!_source.getDay(DateTime(month.year, month.month, d)).isEmpty) {
        count++;
      }
    }
    return count;
  }

  Widget _weekdayHeader(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final monday = DateTime(2024, 1, 1); // a Monday
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing12),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(
                  DateFormat.E(locale)
                      .format(monday.add(Duration(days: i)))
                      .substring(0, 1)
                      .toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _monthGrid(BuildContext context, DateTime month) {
    final first = DateTime(month.year, month.month);
    final leading = first.weekday - 1; // Monday first
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final cells = leading + days;
    final rows = (cells / 7).ceil();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing12),
      child: Column(
        children: [
          for (var r = 0; r < rows; r++)
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final index = r * 7 + c - leading;
                          if (index < 0 || index >= days) {
                            return const SizedBox.shrink();
                          }
                          return _dayCell(
                            context,
                            DateTime(month.year, month.month, index + 1),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime date) {
    final others = _others;
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final plan = _source.getDay(date);
    final today = DayPlan.dateOnly(DateTime.now());
    final selecting = _picked.isNotEmpty;
    final selected = selecting ? _picked.contains(date) : date == _selected;
    final isToday = date == today;
    final daily = _budget?.daily.total;
    final planned = plan.totalPoints.total;
    final fill = daily == null || daily <= 0
        ? (plan.isEmpty ? 0.0 : 1.0)
        : (planned / daily).clamp(0.0, 1.0);
    final over = daily != null && planned > daily + 0.001;
    final status = plan.isEmpty
        ? null
        : plan.fullyLogged
        ? scheme.primary
        : plan.logged.isNotEmpty
        ? const Color(0xFFFFB300)
        : scheme.outline;
    final format = PointsFormat.of(context);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        identifier: 'planner-calendar-${DayPlan.dateKey(date)}',
        button: true,
        selected: selected,
        label: [
          DateFormat.MMMMEEEEd(locale).format(date),
          if (!plan.isEmpty)
            '${format.points(planned)} ${S.of(context).pointsShort}',
        ].join(', '),
        excludeSemantics: true,
        child: Material(
          color: selected
              ? scheme.primary
              : plan.isEmpty
              ? Colors.transparent
              : scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: Dimens.borderRadiusM,
            side: isToday
                ? BorderSide(color: scheme.primary, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: Dimens.borderRadiusM,
            onTap: () => selecting ? _togglePick(date) : _openDay(date),
            onLongPress: () => _togglePick(date),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontWeight: isToday || selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected ? scheme.onPrimary : null,
                        ),
                      ),
                      for (final member in others)
                        if (!(member.dayFor(date)?.isEmpty ?? true))
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(left: 2),
                            decoration: BoxDecoration(
                              color: memberColor(member.memberId),
                              shape: BoxShape.circle,
                            ),
                          ),
                    ],
                  ),
                  if (!plan.isEmpty)
                    Text(
                      format.points(PointsCalc.snapToStep(planned)),
                      style: TextStyle(
                        fontSize: 10,
                        color: selected
                            ? scheme.onPrimary
                            : over
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 4,
                      child: LinearProgressIndicator(
                        value: fill,
                        backgroundColor: plan.isEmpty
                            ? Colors.transparent
                            : scheme.outlineVariant,
                        color: selected
                            ? scheme.onPrimary
                            : over
                            ? scheme.error
                            : status,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing8,
        Dimens.spacing16,
        Dimens.spacing8,
      ),
      child: Wrap(
        spacing: Dimens.spacing16,
        runSpacing: Dimens.spacing4,
        children: [
          item(scheme.outline, s.plannerCalendarLegendPlanned),
          item(const Color(0xFFFFB300), s.plannerCalendarLegendPartly),
          item(scheme.primary, s.plannerCalendarLegendLogged),
          item(scheme.error, s.plannerCalendarLegendOver),
        ],
      ),
    );
  }

  // ---- EatPoint: one day's meals, everyone's, in a sheet. ----

  /// Opens [date]'s meals: the user's and every member's. "Go to this day"
  /// or a meal returns to the weekly menu there.
  Future<void> _openDay(DateTime date) async {
    setState(() => _selected = date);
    final pick = await showModalBottomSheet<PlannerCalendarPick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListenableBuilder(
          listenable: Listenable.merge([
            _source.revision,
            ?_household?.revision,
          ]),
          builder: (context, _) => _daySheet(context, date, scroll),
        ),
      ),
    );
    if (pick != null && mounted) Navigator.of(context).pop(pick);
  }

  Widget _daySheet(
    BuildContext context,
    DateTime date,
    ScrollController scroll,
  ) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final format = PointsFormat.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final household = _household?.getHousehold();
    final plan = _source.getDay(date);
    final slots = _mySlots;
    final mine = [
      ...slots,
      for (final id in plan.meals.keys)
        if (slots.byId(id) == null && plan.itemsFor(id).isNotEmpty)
          MealSlot(
            id: id,
            baseType:
                MealSlot.dayOrder.where((t) => t.name == id).firstOrNull ??
                MealSlot.dayOrder.last,
            share: MacroPoints.zero,
          ),
    ].where((slot) => plan.itemsFor(slot.id).isNotEmpty).toList();
    final daily = _budget?.daily;

    Widget empty() => Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
      child: Text(
        s.plannerCalendarEmptyDay,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        0,
        Dimens.spacing16,
        Dimens.spacing24,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                toBeginningOfSentenceCase(
                  DateFormat.MMMMEEEEd(locale).format(date),
                ),
                style: theme.textTheme.titleMedium,
              ),
            ),
            Semantics(
              identifier: 'planner-calendar-open-day',
              child: FilledButton.tonalIcon(
                onPressed: () =>
                    Navigator.of(context).pop(PlannerCalendarPick(date)),
                icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                label: Text(s.plannerCalendarOpenDay),
              ),
            ),
          ],
        ),
        if (household != null)
          _ownerHeader(
            context,
            household.memberName,
            household.memberId,
            s.householdYou(household.memberName),
          ),
        const SizedBox(height: Dimens.spacing8),
        if (daily != null && !plan.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Dimens.spacing8),
            child: _PointsBar(
              planned: plan.totalPoints,
              daily: daily,
              carbs: palette.carbs,
              protein: palette.protein,
              fat: palette.fat,
              label: s.plannerDayPoints(
                format.points(plan.totalPoints.total),
                format.points(daily.total),
              ),
            ),
          ),
        if (mine.isEmpty) empty(),
        for (final slot in mine)
          _sheetMeal(
            context,
            date: date,
            day: plan,
            slot: slot,
            name: slots.byId(slot.id) == null
                ? s.plannerOtherMeal
                : mealSlotLabel(context, slot),
            colourKey: household?.memberId,
            canDelete: true,
            onOpen: () => Navigator.of(
              context,
            ).pop(PlannerCalendarPick(date, slotId: slot.id)),
            onDelete: () => _deleteMeal(null, date, slot.id),
          ),
        for (final member in _others) ...[
          const SizedBox(height: Dimens.spacing8),
          _ownerHeader(
            context,
            member.name,
            member.memberId,
            s.householdMemberMenu(member.name),
            readOnly: !member.allowsEdits,
          ),
          const SizedBox(height: Dimens.spacing8),
          if (member.dayFor(date)?.isEmpty ?? true) empty(),
          if (member.dayFor(date) case final day?)
            for (final slot in memberSlots(member, day))
              if (day.itemsFor(slot.id).isNotEmpty)
                _sheetMeal(
                  context,
                  date: date,
                  day: day,
                  slot: slot,
                  name: mealSlotLabel(context, slot),
                  colourKey: member.memberId,
                  canDelete: member.allowsEdits,
                  onOpen: () => Navigator.of(context).pop(
                    PlannerCalendarPick(
                      date,
                      memberId: member.memberId,
                      slotId: slot.id,
                    ),
                  ),
                  onDelete: () => _deleteMeal(member.memberId, date, slot.id),
                ),
        ],
      ],
    );
  }

  Widget _ownerHeader(
    BuildContext context,
    String name,
    String colourKey,
    String title, {
    bool readOnly = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Dimens.spacing12),
      child: Row(
        children: [
          MemberAvatar(name: name, colourKey: colourKey),
          const SizedBox(width: Dimens.spacing8),
          Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
          if (readOnly)
            Text(
              S.of(context).plannerReadOnly,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// One meal in the day's sheet, in its owner's colour. Tap to open it in
  /// the weekly menu; swipe left to delete it, after asking.
  Widget _sheetMeal(
    BuildContext context, {
    required DateTime date,
    required DayPlan day,
    required MealSlot slot,
    required String name,
    required String? colourKey,
    required bool canDelete,
    required VoidCallback onOpen,
    required Future<void> Function() onDelete,
  }) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = PointsFormat.of(context);
    final accent = colourKey == null ? scheme.primary : memberColor(colourKey);
    final logged = day.logged.contains(slot.id);
    final key = '${colourKey ?? 'me'}-${DayPlan.dateKey(date)}-${slot.id}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
      child: Dismissible(
        key: ValueKey('calendar-meal-$key'),
        direction: canDelete
            ? DismissDirection.endToStart
            : DismissDirection.none,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: Dimens.borderRadiusM,
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            color: scheme.onErrorContainer,
          ),
        ),
        confirmDismiss: (_) async {
          final ok = await _confirmDeleteMeal(context, name);
          if (ok) await onDelete();
          return ok;
        },
        child: Semantics(
          identifier: 'calendar-meal-$key',
          button: true,
          child: Material(
            color: Color.alphaBlend(
              accent.withValues(alpha: 0.12),
              scheme.surfaceContainerLow,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: Dimens.borderRadiusM,
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
            ),
            child: InkWell(
              borderRadius: Dimens.borderRadiusM,
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      logged ? Icons.check_circle_rounded : mealSlotIcon(slot),
                      size: 20,
                      color: accent,
                    ),
                    const SizedBox(width: Dimens.spacing8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: theme.textTheme.titleSmall),
                          Text(
                            day
                                .itemsFor(slot.id)
                                .map((i) => i.name)
                                .join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${format.points(day.pointsFor(slot.id).total)} '
                      '${s.pointsShort}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
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
  }

  Future<bool> _confirmDeleteMeal(BuildContext context, String meal) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.plannerConfirmDeleteMeal(meal)),
        content: Text(s.plannerDeleteMealBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.plannerDeleteDay),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Empties one meal of [memberId]'s menu (null: the user's). The user's
  /// diary is not touched; a member's change goes to their phone.
  Future<void> _deleteMeal(
    String? memberId,
    DateTime date,
    String slotId,
  ) async {
    if (memberId == null) {
      final day = _source.getDay(date);
      await _source.saveDay(
        day.withMeal(slotId, const []).withLogged(slotId, false),
      );
      return;
    }
    await _sendEdit(memberId, date, slotId, const []);
    HouseholdAutoSync.instance.syncSoon(Duration.zero);
  }

  Future<void> _sendEdit(
    String memberId,
    DateTime date,
    String slotId,
    List<PlannedItem> items,
  ) async {
    final store = _household;
    if (store == null) return;
    await store.editMemberMenu(
      MenuEdit(
        id: IdGenerator.getUniqueID(),
        memberId: memberId,
        date: date,
        slotId: slotId,
        items: items,
        by: store.getHousehold()?.memberName ?? '',
        at: DateTime.now(),
      ),
    );
  }

  // ---- EatPoint: choosing several days. ----

  List<DateTime> get _pickedSorted => _picked.toList()..sort();

  void _togglePick(DateTime date) => setState(() {
    if (!_picked.remove(date)) _picked.add(date);
  });

  Widget _selectionBar(BuildContext context) {
    final s = S.of(context);
    Widget action(String id, IconData icon, String label, VoidCallback onTap) =>
        Semantics(
          identifier: 'calendar-$id',
          child: FilledButton.tonalIcon(
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
        );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing8,
          Dimens.spacing16,
          Dimens.spacing16,
        ),
        child: Wrap(
          spacing: Dimens.spacing8,
          runSpacing: Dimens.spacing8,
          alignment: WrapAlignment.center,
          children: [
            action(
              'delete',
              Icons.delete_sweep_outlined,
              s.calendarDeleteMenus,
              _deletePicked,
            ),
            action(
              'generate',
              Icons.auto_awesome_rounded,
              s.generatorTitle,
              _generatePicked,
            ),
            action(
              'import',
              Icons.file_download_outlined,
              s.menuImportTitle,
              _importPicked,
            ),
            action(
              'copy',
              Icons.content_copy_rounded,
              s.calendarCopyDay,
              _copyToPicked,
            ),
            action(
              'travel',
              Icons.flight_takeoff_rounded,
              s.calendarTravel,
              _travelPicked,
            ),
          ],
        ),
      ),
    );
  }

  /// Deletes the chosen days' menus: the user's, and those of the members
  /// picked who allow it. Can be undone.
  Future<void> _deletePicked() async {
    final s = S.of(context);
    final household = _household?.getHousehold();
    final others = _others;
    final whose = <String?>{null};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(s.calendarDeleteWhose),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: whose.contains(null),
                title: Text(
                  household == null
                      ? s.plannerTitle
                      : s.householdYou(household.memberName),
                ),
                onChanged: (v) => setDialogState(
                  () => v! ? whose.add(null) : whose.remove(null),
                ),
              ),
              for (final m in others)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: whose.contains(m.memberId),
                  title: Text(m.name),
                  subtitle: m.allowsEdits ? null : Text(s.plannerReadOnly),
                  onChanged: m.allowsEdits
                      ? (v) => setDialogState(
                          () => v!
                              ? whose.add(m.memberId)
                              : whose.remove(m.memberId),
                        )
                      : null,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: whose.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: Text(s.plannerDeleteDay),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final mine = <DayPlan>[];
    final theirs =
        <
          ({String member, DateTime date, String slot, List<PlannedItem> items})
        >[];
    for (final date in _pickedSorted) {
      if (whose.contains(null)) {
        final before = _source.getDay(date);
        if (!before.isEmpty) {
          mine.add(before);
          await _source.saveDay(DayPlan.empty(date));
        }
      }
      for (final m in others) {
        if (!whose.contains(m.memberId) || !m.allowsEdits) continue;
        final day = m.dayFor(date);
        if (day == null) continue;
        for (final slot in day.meals.keys) {
          final items = day.itemsFor(slot);
          if (items.isEmpty) continue;
          theirs.add((
            member: m.memberId,
            date: date,
            slot: slot,
            items: items,
          ));
          await _sendEdit(m.memberId, date, slot, const []);
        }
      }
    }
    if (theirs.isNotEmpty) HouseholdAutoSync.instance.syncSoon(Duration.zero);
    setState(_picked.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.calendarDeletedMenus),
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: s.plannerUndo,
          onPressed: () async {
            for (final day in mine) {
              await _source.saveDay(day);
            }
            for (final t in theirs) {
              await _sendEdit(t.member, t.date, t.slot, t.items);
            }
            if (theirs.isNotEmpty) {
              HouseholdAutoSync.instance.syncSoon(Duration.zero);
            }
          },
        ),
      ),
    );
  }

  /// Plans the chosen days (from the first to the last) with the
  /// generator.
  Future<void> _generatePicked() async {
    final days = _pickedSorted;
    final span = days.last.difference(days.first).inDays + 1;
    final messenger = ScaffoldMessenger.of(context);
    final done = S.of(context).generatorDone;
    final planned = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) =>
            MenuGeneratorScreen(initialDay: days.first, initialDays: span),
      ),
    );
    if (!mounted) return;
    setState(_picked.clear);
    if (planned != null && planned > 0) {
      messenger.showSnackBar(SnackBar(content: Text(done('$planned'))));
    }
  }

  Future<void> _importPicked() async {
    final first = _pickedSorted.first;
    final messenger = ScaffoldMessenger.of(context);
    final done = S.of(context).menuImportDone;
    final imported = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => MenuImportScreen(initialWeek: first)),
    );
    if (!mounted) return;
    setState(_picked.clear);
    if (imported != null && imported > 0) {
      messenger.showSnackBar(SnackBar(content: Text(done('$imported'))));
    }
  }

  /// Copies one day's menu (picked from a date picker) onto the chosen
  /// days.
  Future<void> _copyToPicked() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final source = await showDatePicker(
      context: context,
      helpText: s.calendarCopyDayPick,
      initialDate: _selected,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (source == null || !mounted) return;
    final plan = _source.getDay(DayPlan.dateOnly(source));
    if (plan.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.plannerNothingToCopy)));
      return;
    }
    var copied = 0;
    for (final date in _pickedSorted) {
      if (date == plan.date) continue;
      await _source.saveDay(plan.copyTo(date));
      copied++;
    }
    setState(_picked.clear);
    messenger.showSnackBar(
      SnackBar(content: Text(s.calendarCopied('$copied'))),
    );
  }

  /// Marks the chosen days, from the first to the last, as a trip.
  Future<void> _travelPicked() async {
    final s = S.of(context);
    final locale = Localizations.localeOf(context).toString();
    final days = _pickedSorted;
    final from = DateFormat.MMMd(locale).format(days.first);
    final to = DateFormat.MMMd(locale).format(days.last);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.calendarTravelConfirm(from, to)),
        content: Text(s.calendarTravelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (locator.isRegistered<TravelModeStore>()) {
      await locator<TravelModeStore>().planTrip(days.first, days.last);
    }
    setState(_picked.clear);
    messenger.showSnackBar(
      SnackBar(content: Text(s.calendarTravelPlanned(from, to))),
    );
  }
}

class _PointsBar extends StatelessWidget {
  final MacroPoints planned;
  final MacroPoints daily;
  final Color carbs;
  final Color protein;
  final Color fat;
  final String label;

  const _PointsBar({
    required this.planned,
    required this.daily,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final total = daily.total <= 0 ? 1.0 : daily.total;
    int flex(double v) => (v / total * 1000).round().clamp(0, 1000);
    final rest = (1000 - flex(planned.total)).clamp(0, 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (planned.carbs > 0)
                  Expanded(
                    flex: flex(planned.carbs),
                    child: ColoredBox(color: carbs),
                  ),
                if (planned.protein > 0)
                  Expanded(
                    flex: flex(planned.protein),
                    child: ColoredBox(color: protein),
                  ),
                if (planned.fat > 0)
                  Expanded(
                    flex: flex(planned.fat),
                    child: ColoredBox(color: fat),
                  ),
                if (rest > 0)
                  Expanded(
                    flex: rest,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
