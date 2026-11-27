import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_rebalance_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/mcp/data/mcp_controller.dart';
import 'package:opennutritracker/features/planner/presentation/planner_screen.dart';
import 'package:opennutritracker/features/sync/domain/household_auto_sync.dart';
import 'package:opennutritracker/features/planner/presentation/shopping_list_screen.dart';
import 'package:opennutritracker/features/points/data/meal_slot_assignments.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_colors.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/features/points/presentation/points_settings_screen.dart';
import 'package:opennutritracker/features/points/presentation/widgets/points_budget_guide_sheet.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/features/travel/presentation/travel_mode_actions.dart';
import 'package:opennutritracker/features/travel/presentation/travel_mode_banner.dart';
import 'package:opennutritracker/features/travel/presentation/travel_mode_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Shows the points card on the home screen while points mode is on, and
/// the original calorie dashboard ([caloriesView]) otherwise, with a chip
/// to switch between them.
class PointsHomeSwitcher extends StatefulWidget {
  final Widget caloriesView;
  final Map<IntakeTypeEntity, List<IntakeEntity>> intakes;
  final double kcalSupplied;
  final double kcalGoal;

  const PointsHomeSwitcher({
    super.key,
    required this.caloriesView,
    required this.intakes,
    required this.kcalSupplied,
    required this.kcalGoal,
  });

  @override
  State<PointsHomeSwitcher> createState() => _PointsHomeSwitcherState();
}

class _PointsHomeSwitcherState extends State<PointsHomeSwitcher> {
  /// Points need their settings store; without it (a build or test that
  /// does not register EatPoint's services) this is the original dashboard.
  final bool _available = locator.isRegistered<PointsSettingsDataSource>();
  late final PointsSettingsDataSource? _settings = _available
      ? locator<PointsSettingsDataSource>()
      : null;
  PointsBudgetResult? _budget;
  bool _loaded = false;
  bool _guideShown = false;

  @override
  void initState() {
    super.initState();
    if (!_available) return;
    _settings!.revision.addListener(_load);
    if (locator.isRegistered<MealSlotAssignments>()) {
      locator<MealSlotAssignments>().revision.addListener(_load);
    }
    if (locator.isRegistered<TravelModeStore>()) {
      locator<TravelModeStore>().revision.addListener(_onTravelChanged);
    }
    _load();
    _startConnectedServices();
    _lifecycle = AppLifecycleListener(onResume: _startConnectedServices);
  }

  @override
  void dispose() {
    _settings?.revision.removeListener(_load);
    if (locator.isRegistered<MealSlotAssignments>()) {
      locator<MealSlotAssignments>().revision.removeListener(_load);
    }
    if (locator.isRegistered<TravelModeStore>()) {
      locator<TravelModeStore>().revision.removeListener(_onTravelChanged);
    }
    _lifecycle?.dispose();
    super.dispose();
  }

  AppLifecycleListener? _lifecycle;

  /// The agent connector and the household sync run while the app is in
  /// the foreground; the home screen is where the app comes back to.
  void _onTravelChanged() {
    if (mounted) setState(() {});
  }

  void _startConnectedServices() {
    // Reads the locale, so not during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) TravelModeActions.endIfExpired(context);
    });
    if (locator.isRegistered<McpController>()) {
      locator<McpController>().applyConfig().catchError((_) {});
    }
    HouseholdAutoSync.instance.syncSoon(Duration.zero);
  }

  Future<void> _load() async {
    try {
      final budget = await locator<GetPointsBudgetUsecase>().getBudget();
      if (!mounted) return;
      setState(() {
        _budget = budget;
        _loaded = true;
      });
      _maybeShowGuide(budget);
    } catch (_) {
      // No user profile yet (onboarding not finished): calorie view.
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _maybeShowGuide(PointsBudgetResult budget) {
    if (_guideShown ||
        !budget.settings.pointsModeEnabled ||
        budget.settings.budgetGuideAcknowledged) {
      return;
    }
    _guideShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PointsBudgetGuideSheet.show(context, budget);
    });
  }

  Future<void> _setPointsMode(bool enabled) async {
    final settings = _settings;
    if (settings == null) return;
    final current = await settings.getSettings();
    await settings.saveSettings(current.copyWith(pointsModeEnabled: enabled));
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return widget.caloriesView;
    final budget = _budget;
    final pointsMode =
        _loaded && budget != null && budget.settings.pointsModeEnabled;
    final travel = TravelModeGate.active;
    final shortcuts = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (travel) const TravelModeBanner(),
        if (!TravelModeGate.plannerPaused || !travel)
          _PlannerShortcuts(
            showTravel: !travel,
            trailing: pointsMode || budget == null
                ? null
                : Semantics(
                    identifier: 'home-switch-to-points',
                    child: ActionChip(
                      avatar: const Icon(Icons.donut_large_rounded, size: 18),
                      label: Text(S.of(context).pointsPointsViewLabel),
                      onPressed: () => _setPointsMode(true),
                    ),
                  ),
          ),
      ],
    );
    if (!pointsMode) {
      return Column(children: [shortcuts, widget.caloriesView]);
    }
    return Column(
      children: [
        shortcuts,
        _PointsDayCard(
          budget: budget,
          intakes: widget.intakes,
          kcalSupplied: widget.kcalSupplied,
          kcalGoal: widget.kcalGoal,
          onSwitchToCalories: () => _setPointsMode(false),
        ),
      ],
    );
  }
}

/// One-tap access to the weekly menu and the shopping list.
class _PlannerShortcuts extends StatelessWidget {
  final Widget? trailing;
  final bool showTravel;

  const _PlannerShortcuts({this.trailing, this.showTravel = true});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing4,
        Dimens.spacing16,
        0,
      ),
      child: Wrap(
        spacing: Dimens.spacing8,
        runSpacing: Dimens.spacing4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            identifier: 'home-open-planner',
            child: ActionChip(
              avatar: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(s.plannerEntry),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const PlannerScreen())),
            ),
          ),
          Semantics(
            identifier: 'home-open-shopping',
            child: ActionChip(
              avatar: const Icon(Icons.shopping_cart_outlined, size: 18),
              label: Text(s.shoppingEntry),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ShoppingListScreen(weekOf: DateTime.now()),
                ),
              ),
            ),
          ),
          if (showTravel)
            Semantics(
              identifier: 'home-travel-mode',
              child: ActionChip(
                avatar: const Icon(Icons.flight_takeoff_rounded, size: 18),
                label: Text(s.travelTitle),
                onPressed: () => showTravelModeSheet(context),
              ),
            ),
          ?trailing,
        ],
      ),
    );
  }
}

class _PointsDayCard extends StatelessWidget {
  final PointsBudgetResult budget;
  final Map<IntakeTypeEntity, List<IntakeEntity>> intakes;
  final double kcalSupplied;
  final double kcalGoal;
  final VoidCallback onSwitchToCalories;

  const _PointsDayCard({
    required this.budget,
    required this.intakes,
    required this.kcalSupplied,
    required this.kcalGoal,
    required this.onSwitchToCalories,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final format = PointsFormat.of(context);

    final used = intakes.values
        .map((list) => list.macroPoints)
        .fold(MacroPoints.zero, (a, b) => a + b);
    final fibreUsed = intakes.values.fold(
      0.0,
      (sum, list) => sum + list.fibrePoints,
    );
    final slots = budget.slots;
    final grouping = locator.isRegistered<MealSlotAssignments>()
        ? locator<MealSlotAssignments>().group(
            intakes.values.expand((list) => list),
            slots,
          )
        : null;
    final usedPerSlot = {
      for (final slot in slots)
        slot.id:
            (grouping?.bySlot[slot.id] ?? const <IntakeEntity>[]).macroPoints,
    };
    // What a meal went over is taken off the meals still ahead today.
    final perSlot = budget.settings.rebalanceOverspend
        ? PointsRebalanceCalc.rebalance(
            order: [for (final slot in slots) slot.id],
            budgets: budget.perSlot,
            used: usedPerSlot,
          )
        : budget.perSlot;
    final dailyOnly = TravelModeGate.dailyBudgetOnly;
    final daily = budget.daily;
    final left = daily.total - used.total;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing16,
        vertical: Dimens.spacing8,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: Dimens.borderRadiusL,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PointsSettingsScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.pointsDayTitle,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Semantics(
                      identifier: 'home-switch-to-calories',
                      child: TextButton.icon(
                        onPressed: onSwitchToCalories,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: Text(s.pointsCaloriesViewLabel),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Dimens.spacing8),
                Row(
                  children: [
                    SizedBox(
                      width: 136,
                      height: 136,
                      child: CustomPaint(
                        painter: _RingPainter(
                          budget: daily,
                          used: used,
                          track: palette.border,
                          carbs: palette.carbs,
                          protein: palette.protein,
                          fat: palette.fat,
                        ),
                        child: Center(
                          child: Semantics(
                            label:
                                '${format.points(left.abs())} ${left >= 0 ? s.pointsLeftLabel : s.pointsOverLabel}',
                            excludeSemantics: true,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  format.points(left.abs()),
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: left >= 0
                                            ? null
                                            : theme.colorScheme.error,
                                      ),
                                ),
                                Text(
                                  left >= 0
                                      ? s.pointsLeftLabel
                                      : s.pointsOverLabel,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Dimens.spacing16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MacroLine(
                            label: s.pointsCarbsLabel,
                            color: palette.carbs,
                            text: s.pointsUsedOfBudget(
                              format.points(used.carbs),
                              format.points(daily.carbs),
                            ),
                          ),
                          _MacroLine(
                            label: s.pointsProteinLabel,
                            color: palette.protein,
                            text: s.pointsUsedOfBudget(
                              format.points(used.protein),
                              format.points(daily.protein),
                            ),
                          ),
                          _MacroLine(
                            label: s.pointsFatLabel,
                            color: palette.fat,
                            text: s.pointsUsedOfBudget(
                              format.points(used.fat),
                              format.points(daily.fat),
                            ),
                          ),
                          if (budget.fibreDaily > 0)
                            _MacroLine(
                              label: s.pointsFibreLabel,
                              color: PointsColors.fibre,
                              text: s.pointsFibreOfMin(
                                format.points(fibreUsed),
                                format.points(budget.fibreDaily),
                              ),
                              highlight: fibreUsed + 0.001 >= budget.fibreDaily
                                  ? PointsColors.fibre
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Dimens.spacing12),
                Text(
                  s.pointsKcalLine(
                    kcalSupplied.round().toString(),
                    kcalGoal.round().toString(),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!dailyOnly) const Divider(height: Dimens.spacing24),
                if (!dailyOnly)
                  Wrap(
                    spacing: Dimens.spacing16,
                    runSpacing: Dimens.spacing4,
                    children: [
                      for (final slot in slots)
                        if (perSlot[slot.id] case final slotBudget?)
                          _MealUsageText(
                            text: s.pointsMealUsage(
                              mealSlotLabel(context, slot),
                              format.points(usedPerSlot[slot.id]!.total),
                              format.points(slotBudget.total),
                            ),
                            over:
                                usedPerSlot[slot.id]!.total >
                                slotBudget.total + 0.001,
                            lowered:
                                (budget.perSlot[slot.id]!.total -
                                        slotBudget.total)
                                    .abs() >
                                0.001,
                            loweredLabel: s.pointsMealLoweredTooltip,
                          ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Lunch: 2 / 6 pts" on the points card, in red when over, with a small
/// arrow when the budget was lowered to make up for an earlier meal.
class _MealUsageText extends StatelessWidget {
  final String text;
  final bool over;
  final bool lowered;
  final String loweredLabel;

  const _MealUsageText({
    required this.text,
    required this.over,
    required this.lowered,
    required this.loweredLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontWeight: over ? FontWeight.w700 : null,
      color: over ? theme.colorScheme.error : null,
    );
    return Text.rich(
      TextSpan(
        text: text,
        children: [
          if (lowered)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Tooltip(
                message: loweredLabel,
                child: Icon(
                  Icons.south_rounded,
                  size: 13,
                  semanticLabel: loweredLabel,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      style: style,
    );
  }
}

class _MacroLine extends StatelessWidget {
  final String label;
  final Color color;
  final String text;

  /// Colour of [text] when it should stand out (fibre minimum reached).
  final Color? highlight;

  const _MacroLine({
    required this.label,
    required this.color,
    required this.text,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimens.spacing4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Dimens.spacing8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlight,
            ),
          ),
        ],
      ),
    );
  }
}

/// A ring split into three arcs sized by each macro's daily budget; each
/// arc fills with what has been used of that macro.
class _RingPainter extends CustomPainter {
  final MacroPoints budget;
  final MacroPoints used;
  final Color track;
  final Color carbs;
  final Color protein;
  final Color fat;

  _RingPainter({
    required this.budget,
    required this.used,
    required this.track,
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    const gap = 0.06;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    final total = budget.total;
    final background = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (total <= 0) {
      canvas.drawArc(rect, 0, 2 * math.pi, false, background);
      return;
    }
    var start = -math.pi / 2;
    for (final (b, u, color) in [
      (budget.carbs, used.carbs, carbs),
      (budget.protein, used.protein, protein),
      (budget.fat, used.fat, fat),
    ]) {
      final sweep = 2 * math.pi * b / total;
      if (sweep <= gap) {
        start += sweep;
        continue;
      }
      final arcSweep = sweep - gap;
      canvas.drawArc(
        rect,
        start + gap / 2,
        arcSweep,
        false,
        background..color = color.withValues(alpha: 0.2),
      );
      final fill = (b <= 0 ? 0.0 : (u / b)).clamp(0.0, 1.0);
      if (fill > 0) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          arcSweep * fill,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.budget != budget || old.used != used || old.track != track;
}
