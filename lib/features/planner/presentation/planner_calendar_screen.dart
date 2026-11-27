import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// A month view of the menu: every day shows how much of the daily budget
/// is planned and whether it was logged. Tapping a day previews it; "Open
/// this day" returns the date to the weekly menu.
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

  @override
  void initState() {
    super.initState();
    _source.revision.addListener(_refresh);
    _loadBudget();
  }

  @override
  void dispose() {
    _source.revision.removeListener(_refresh);
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

    return Scaffold(
      appBar: AppBar(
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
              onPageChanged: (page) => setState(() => _month = _monthAt(page)),
              itemBuilder: (context, page) =>
                  _monthGrid(context, _monthAt(page)),
            ),
          ),
          _legend(context),
          const Divider(height: 1),
          Expanded(child: _dayPreview(context)),
        ],
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
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final plan = _source.getDay(date);
    final today = DayPlan.dateOnly(DateTime.now());
    final selected = date == _selected;
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
            onTap: () => setState(() => _selected = date),
            onDoubleTap: () => Navigator.of(context).pop(date),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

  Widget _dayPreview(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final format = PointsFormat.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final plan = _source.getDay(_selected);
    final slots = _budget?.slots.isNotEmpty == true
        ? _budget!.slots
        : MealSlot.builtIn();
    final ids = [
      for (final slot in slots)
        if (plan.itemsFor(slot.id).isNotEmpty) slot.id,
      for (final id in plan.meals.keys)
        if (slots.byId(id) == null && plan.itemsFor(id).isNotEmpty) id,
    ];
    final daily = _budget?.daily;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing12,
        Dimens.spacing16,
        Dimens.spacing16,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                toBeginningOfSentenceCase(
                  DateFormat.MMMMEEEEd(locale).format(_selected),
                ),
                style: theme.textTheme.titleMedium,
              ),
            ),
            Semantics(
              identifier: 'planner-calendar-open-day',
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).pop(_selected),
                icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                label: Text(s.plannerCalendarOpenDay),
              ),
            ),
          ],
        ),
        const SizedBox(height: Dimens.spacing8),
        if (plan.isEmpty)
          Text(
            s.plannerCalendarEmptyDay,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          if (daily != null)
            _PointsBar(
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
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    plan.logged.contains(id)
                        ? Icons.check_circle_rounded
                        : (slots.byId(id) == null
                              ? Icons.restaurant_rounded
                              : mealSlotIcon(slots.byId(id)!)),
                    size: 18,
                    color: plan.logged.contains(id)
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Dimens.spacing8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slots.byId(id) == null
                              ? s.plannerOtherMeal
                              : mealSlotLabel(context, slots.byId(id)!),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          plan.itemsFor(id).map((i) => i.name).join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${format.points(plan.pointsFor(id).total)} ${s.pointsShort}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
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
