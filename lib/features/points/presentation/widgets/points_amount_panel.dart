import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/points/data/meal_slot_assignments.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_day_meal_budgets_usecase.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_meal_points_usage_usecase.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The points half of the amount sheet: a points field kept in sync with
/// the grams field, quarter-point steps, the practical-grams note and the
/// "fit in your meal" strip.
///
/// The grams field stays the source of truth for what gets logged. Typing
/// points writes rounded grams into [quantityController] (switching the
/// unit to g or ml through [onQuantityOrUnitChanged]); typing grams
/// updates the points shown here from the bloc's computed energy.
class PointsAmountPanel extends StatefulWidget {
  final MealEntity product;
  final DateTime day;
  final IntakeTypeEntity intakeType;
  final MealDetailBloc mealDetailBloc;
  final TextEditingController quantityController;
  final void Function(String? quantity, String? unit) onQuantityOrUnitChanged;

  /// When false only a one-line summary is shown (the sheet is collapsed).
  final bool expanded;

  const PointsAmountPanel({
    super.key,
    required this.product,
    required this.day,
    required this.intakeType,
    required this.mealDetailBloc,
    required this.quantityController,
    required this.onQuantityOrUnitChanged,
    this.expanded = true,
  });

  @override
  State<PointsAmountPanel> createState() => _PointsAmountPanelState();
}

class _PointsAmountPanelState extends State<PointsAmountPanel> {
  static const _quickPoints = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0];

  final _pointsController = TextEditingController();
  final _pointsFocus = FocusNode();

  /// Set while the user drives the amount from the points field, so the
  /// echo from the bloc does not overwrite what they typed.
  PointsToGramsResult? _lastConversion;

  MacroPoints? _mealBudget;
  MacroPoints _mealUsed = MacroPoints.zero;

  /// The meal the strip compares against; null when it shows the whole day
  /// (travel mode's daily budget only).
  MealSlot? _mealSlot;

  /// How many points this meal's budget lost to an earlier meal's
  /// overspend, when it did.
  double? _mealAdjustedBy;

  double? get _per100 => widget.product.pointsPer100;

  @override
  void initState() {
    super.initState();
    _loadMealContext();
  }

  bool _initialSyncDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Formatting reads the locale, which is only available from here on.
    if (!_initialSyncDone) {
      _initialSyncDone = true;
      _syncFromKcal(widget.mealDetailBloc.state.totalKcal);
    }
  }

  @override
  void dispose() {
    _pointsController.dispose();
    _pointsFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMealContext() async {
    try {
      final day = await GetDayMealBudgetsUsecase(
        locator<GetPointsBudgetUsecase>(),
        locator<GetMealPointsUsageUsecase>(),
      ).forDay(widget.day);
      // The meal the food is being added to: the one picked on Home or in
      // the Diary, else the first meal of this type.
      final pending = MealSlotContext.pending;
      final slot =
          (pending != null && pending.type == widget.intakeType
              ? day.slots.byId(pending.slotId)
              : null) ??
          day.slots.defaultFor(widget.intakeType);
      if (!mounted) return;
      setState(() {
        if (day.dailyOnly || slot == null) {
          _mealSlot = null;
          _mealBudget = day.daily;
          _mealUsed = day.usedTotal;
          _mealAdjustedBy = null;
        } else {
          _mealSlot = slot;
          _mealBudget = day.effective[slot.id];
          _mealUsed = day.used[slot.id] ?? MacroPoints.zero;
          _mealAdjustedBy = day.isAdjusted(slot.id)
              ? day.base[slot.id]!.total - day.effective[slot.id]!.total
              : null;
        }
      });
    } catch (_) {
      // The strip is a guide; without a profile there is nothing to show.
    }
  }

  void _syncFromKcal(double totalKcal) {
    if (_pointsFocus.hasFocus) return;
    final points = totalKcal / PointsCalc.kcalPerPoint;
    final text = points <= 0 ? '' : _format.points(points);
    if (_pointsController.text != text) _pointsController.text = text;
  }

  PointsFormat get _format => PointsFormat.of(context);

  String get _baseUnit => widget.product.isLiquid ? 'ml' : 'g';

  void _applyPoints(double points) {
    final per100 = _per100;
    if (per100 == null || per100 <= 0) return;
    final result = PointsCalc.pointsToGrams(points, per100);
    setState(() => _lastConversion = points > 0 ? result : null);
    final gramsText = result.roundedGrams == 0
        ? ''
        : _format.grams(result.roundedGrams).replaceAll(',', '.');
    widget.quantityController.text = gramsText;
    widget.onQuantityOrUnitChanged(gramsText, _baseUnit);
  }

  void _onPointsTyped(String text) {
    final value = PointsFormat.parse(text);
    if (value == null) return;
    _applyPoints(value);
  }

  void _step(double delta) {
    final current = PointsFormat.parse(_pointsController.text) ?? 0;
    final next = PointsCalc.snapToStep(
      (current + delta).clamp(0, 99).toDouble(),
    );
    _pointsFocus.unfocus();
    _pointsController.text = next == 0 ? '' : _format.points(next);
    _applyPoints(next);
  }

  void _pick(double points) {
    _pointsFocus.unfocus();
    _pointsController.text = _format.points(points);
    _applyPoints(points);
  }

  @override
  Widget build(BuildContext context) {
    final per100 = _per100;
    if (per100 == null || per100 <= 0) return const SizedBox.shrink();
    return BlocListener<MealDetailBloc, MealDetailState>(
      bloc: widget.mealDetailBloc,
      listenWhen: (a, b) => a.totalKcal != b.totalKcal,
      listener: (context, state) {
        _syncFromKcal(state.totalKcal);
        if (!_pointsFocus.hasFocus) setState(() {});
      },
      child: BlocBuilder<MealDetailBloc, MealDetailState>(
        bloc: widget.mealDetailBloc,
        buildWhen: (a, b) => a.totalKcal != b.totalKcal,
        builder: (context, state) {
          final servingPoints = state.totalKcal / PointsCalc.kcalPerPoint;
          final serving = PointsCalc.split(
            servingPoints,
            widget.product.pointsProfile ?? PointsProfile.carbsOnly,
          );
          return AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: widget.expanded
                ? _expanded(context, per100, serving)
                : _collapsed(context, servingPoints),
          );
        },
      ),
    );
  }

  Widget _collapsed(BuildContext context, double points) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.pointsServingSummary(
                _format.points(points),
                _format.points(_per100!),
              ),
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _expanded(BuildContext context, double per100, MacroPoints serving) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final gramsPerPoint = PointsCalc.gramsPerPoint(per100)!;
    final conversion = _lastConversion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Dimens.spacing8,
          runSpacing: Dimens.spacing4,
          children: [
            _InfoChip(
              label: s.pointsPer100Label(_format.points(per100), _baseUnit),
              highlighted: true,
            ),
            _InfoChip(
              label: s.pointsOnePointIs(
                _format.grams(gramsPerPoint),
                _baseUnit,
              ),
            ),
          ],
        ),
        const SizedBox(height: Dimens.spacing12),
        Row(
          children: [
            Semantics(
              identifier: 'points-step-down',
              child: IconButton.outlined(
                tooltip: s.pointsStepDown,
                onPressed: () => _step(-PointsCalc.pointStep),
                icon: const Icon(Icons.remove_rounded),
              ),
            ),
            const SizedBox(width: Dimens.spacing8),
            Expanded(
              child: Semantics(
                identifier: 'points-field',
                child: TextField(
                  controller: _pointsController,
                  focusNode: _pointsFocus,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,2}([.,]\d{0,2})?$'),
                    ),
                  ],
                  onChanged: _onPointsTyped,
                  decoration: InputDecoration(
                    labelText: s.pointsLabel,
                    suffixText: s.pointsShort,
                    border: const OutlineInputBorder(
                      borderRadius: Dimens.borderRadiusM,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Dimens.spacing8),
            Semantics(
              identifier: 'points-step-up',
              child: IconButton.filled(
                tooltip: s.pointsStepUp,
                onPressed: () => _step(PointsCalc.pointStep),
                icon: const Icon(Icons.add_rounded),
              ),
            ),
          ],
        ),
        if (conversion != null) ...[
          const SizedBox(height: Dimens.spacing8),
          Row(
            children: [
              Icon(
                Icons.scale_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Dimens.spacing8),
              Expanded(
                child: Text(
                  s.pointsExactHint(
                    _format.grams(conversion.exactGrams),
                    _format.grams(conversion.roundedGrams),
                    _baseUnit,
                    _format.points(conversion.realPoints),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Dimens.spacing8),
        Wrap(
          spacing: Dimens.spacing8,
          children: [
            for (final p in _quickPoints)
              Semantics(
                identifier: 'points-quick-${p.toString().replaceAll('.', '-')}',
                child: ActionChip(
                  label: Text('${_format.points(p)} ${s.pointsShort}'),
                  onPressed: () => _pick(p),
                ),
              ),
          ],
        ),
        if (_mealBudget != null) ...[
          const SizedBox(height: Dimens.spacing12),
          MealFitStrip(
            mealName: _mealSlot == null
                ? s.pointsDayTitle
                : mealSlotLabel(context, _mealSlot!),
            budget: _mealBudget!,
            used: _mealUsed,
            serving: serving,
          ),
          if (_mealAdjustedBy case final lost?)
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing4),
              child: Text(
                s.pointsMealAdjustedNote(_format.points(lost)),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _InfoChip({required this.label, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing12,
        vertical: Dimens.spacing4,
      ),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primaryContainer.withValues(alpha: 0.6)
            : scheme.surfaceContainerHighest,
        borderRadius: Dimens.borderRadiusL,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: highlighted
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Three bars, one per macro, showing what the meal had already used, what
/// this serving adds, and the meal's budget.
class MealFitStrip extends StatelessWidget {
  final String mealName;
  final MacroPoints budget;
  final MacroPoints used;
  final MacroPoints serving;

  const MealFitStrip({
    super.key,
    required this.mealName,
    required this.budget,
    required this.used,
    required this.serving,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final format = PointsFormat.of(context);
    Widget row(String label, Color color, double b, double u, double add) {
      final total = u + add;
      final over = total - b > 0.001;
      return Padding(
        padding: const EdgeInsets.only(bottom: Dimens.spacing4),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: _FitBar(color: color, budget: b, used: u, adding: add),
            ),
            SizedBox(
              width: 76,
              child: Text(
                '${format.points(total)} / ${format.points(b)}',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: over ? Theme.of(context).colorScheme.error : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      label: s.pointsFitInMealTitle(mealName),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.pointsFitInMealTitle(mealName),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: Dimens.spacing4),
          row(
            s.pointsCarbsLabel,
            palette.carbs,
            budget.carbs,
            used.carbs,
            serving.carbs,
          ),
          row(
            s.pointsProteinLabel,
            palette.protein,
            budget.protein,
            used.protein,
            serving.protein,
          ),
          row(s.pointsFatLabel, palette.fat, budget.fat, used.fat, serving.fat),
        ],
      ),
    );
  }
}

class _FitBar extends StatelessWidget {
  final Color color;
  final double budget;
  final double used;
  final double adding;

  const _FitBar({
    required this.color,
    required this.budget,
    required this.used,
    required this.adding,
  });

  @override
  Widget build(BuildContext context) {
    final scale = [budget, used + adding, 0.25].reduce((a, b) => a > b ? a : b);
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            return Stack(
              children: [
                Container(color: color.withValues(alpha: 0.18)),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: w * (used / scale).clamp(0, 1),
                  child: Container(color: color.withValues(alpha: 0.65)),
                ),
                Positioned(
                  left: w * (used / scale).clamp(0, 1),
                  top: 0,
                  bottom: 0,
                  width: w * (adding / scale).clamp(0, 1),
                  child: Container(color: color),
                ),
                if (budget < scale)
                  Positioned(
                    left: w * (budget / scale) - 1,
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: Container(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
