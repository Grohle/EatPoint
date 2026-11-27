import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_budget_calc.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/meal_slots_screen.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Points settings: points mode, how the budget is worked out, optional
/// body measurements, an optional own budget, and the per-meal split.
class PointsSettingsScreen extends StatefulWidget {
  const PointsSettingsScreen({super.key});

  @override
  State<PointsSettingsScreen> createState() => _PointsSettingsScreenState();
}

class _PointsSettingsScreenState extends State<PointsSettingsScreen> {
  final _source = locator<PointsSettingsDataSource>();
  final _usecase = locator<GetPointsBudgetUsecase>();

  PointsSettings? _draft;
  UserEntity? _user;
  PointsBudget? _suggestion;

  final _adjustment = TextEditingController();
  final _protein = TextEditingController();
  final _carbShare = TextEditingController();
  final _activity = TextEditingController();
  final _neck = TextEditingController();
  final _waist = TextEditingController();
  final _hip = TextEditingController();
  final _ownCarbs = TextEditingController();
  final _ownProtein = TextEditingController();
  final _ownFat = TextEditingController();
  final _fibre = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _adjustment,
      _protein,
      _carbShare,
      _activity,
      _neck,
      _waist,
      _hip,
      _ownCarbs,
      _ownProtein,
      _ownFat,
      _fibre,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _source.getSettings();
    final user = await locator<UserRepository>().getUserData();
    if (!mounted) return;
    final format = PointsFormat.of(context);
    String opt(double? v) => v == null ? '' : format.grams(v);
    _adjustment.text = opt(
      settings.calorieAdjustment == null
          ? null
          : settings.calorieAdjustment! * 100,
    );
    _protein.text = format.grams(settings.proteinGramsPerKgLeanMass);
    _carbShare.text = format.grams(settings.carbShareOfRemainder * 100);
    _activity.text = opt(settings.activityMultiplier);
    _neck.text = opt(settings.neckCm);
    _waist.text = opt(settings.waistCm);
    _hip.text = opt(settings.hipCm);
    _fibre.text = format.grams(settings.fibreTargetGrams);
    final own = settings.dailyBudgetOverride;
    if (own != null) {
      _ownCarbs.text = format.points(own.carbs);
      _ownProtein.text = format.points(own.protein);
      _ownFat.text = format.points(own.fat);
    }
    setState(() {
      _draft = settings;
      _user = user;
    });
    await _refreshSuggestion();
  }

  Future<void> _refreshSuggestion() async {
    final draft = _draft;
    final user = _user;
    if (draft == null || user == null) return;
    try {
      final suggestion = await _usecase.suggest(user, draft);
      if (mounted) setState(() => _suggestion = suggestion);
    } catch (_) {
      if (mounted) setState(() => _suggestion = null);
    }
  }

  void _update(PointsSettings Function(PointsSettings) change) {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _draft = change(draft));
    _refreshSuggestion();
  }

  PointsSettings _readFields(PointsSettings base) {
    double? num(TextEditingController c) => PointsFormat.parse(c.text);
    final adjustment = num(_adjustment);
    final protein = num(_protein);
    final carbShare = num(_carbShare);
    MacroPoints? own;
    if (base.dailyBudgetOverride != null) {
      final c = num(_ownCarbs), p = num(_ownProtein), f = num(_ownFat);
      if (c != null && p != null && f != null) {
        own = MacroPoints(
          carbs: PointsCalc.snapToStep(c),
          protein: PointsCalc.snapToStep(p),
          fat: PointsCalc.snapToStep(f),
        );
      } else {
        own = base.dailyBudgetOverride;
      }
    }
    return base.copyWith(
      calorieAdjustment: () => adjustment == null
          ? null
          : (adjustment / 100).clamp(0.4, 1.6).toDouble(),
      proteinGramsPerKgLeanMass: protein?.clamp(0.5, 3.5).toDouble(),
      carbShareOfRemainder: carbShare == null
          ? null
          : (carbShare / 100).clamp(0.0, 1.0).toDouble(),
      activityMultiplier: () {
        final a = num(_activity);
        return a?.clamp(1.0, 2.5).toDouble();
      },
      neckCm: () => num(_neck),
      waistCm: () => num(_waist),
      hipCm: () => num(_hip),
      dailyBudgetOverride: () => own,
      fibreTargetGrams: num(_fibre)?.clamp(0, 150).toDouble(),
    );
  }

  void _onFieldChanged(String _) {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _draft = _readFields(draft));
    _refreshSuggestion();
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    // The meals are edited on their own screen and saved there; keep
    // whatever it stored rather than the copy this screen loaded.
    final stored = await _source.getSettings();
    await _source.saveSettings(
      _readFields(draft).copyWith(mealSlots: () => stored.mealSlots),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.pointsSettingsTitle),
        actions: [
          Semantics(
            identifier: 'points-settings-save',
            child: TextButton(
              onPressed: draft == null ? null : _save,
              child: Text(s.pointsSaveLabel),
            ),
          ),
        ],
      ),
      body: draft == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: Dimens.spacing32),
              children: [
                Semantics(
                  identifier: 'points-settings-mode',
                  child: SwitchListTile(
                    title: Text(s.pointsModeLabel),
                    subtitle: Text(s.pointsModeSubtitle),
                    value: draft.pointsModeEnabled,
                    onChanged: (v) =>
                        _update((d) => d.copyWith(pointsModeEnabled: v)),
                  ),
                ),
                const Divider(),
                _SectionTitle(s.pointsDailyBudgetTitle),
                _budgetSummary(context),
                Semantics(
                  identifier: 'points-settings-own-budget',
                  child: SwitchListTile(
                    title: Text(s.pointsUseOwnBudget),
                    value: draft.dailyBudgetOverride != null,
                    onChanged: (v) {
                      final suggestion = _suggestion?.rounded;
                      if (v && suggestion != null) {
                        final format = PointsFormat.of(context);
                        _ownCarbs.text = format.points(suggestion.carbs);
                        _ownProtein.text = format.points(suggestion.protein);
                        _ownFat.text = format.points(suggestion.fat);
                      }
                      _update(
                        (d) => d.copyWith(
                          dailyBudgetOverride: () =>
                              v ? (suggestion ?? MacroPoints.zero) : null,
                        ),
                      );
                    },
                  ),
                ),
                if (draft.dailyBudgetOverride != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Dimens.spacing16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _ownCarbs,
                            label: s.pointsCarbsLabel,
                            onChanged: _onFieldChanged,
                            id: 'points-own-carbs',
                          ),
                        ),
                        const SizedBox(width: Dimens.spacing8),
                        Expanded(
                          child: _NumberField(
                            controller: _ownProtein,
                            label: s.pointsProteinLabel,
                            onChanged: _onFieldChanged,
                            id: 'points-own-protein',
                          ),
                        ),
                        const SizedBox(width: Dimens.spacing8),
                        Expanded(
                          child: _NumberField(
                            controller: _ownFat,
                            label: s.pointsFatLabel,
                            onChanged: _onFieldChanged,
                            id: 'points-own-fat',
                          ),
                        ),
                      ],
                    ),
                  ),
                _mealSplit(context, draft),
                _fieldRow([
                  _NumberField(
                    controller: _fibre,
                    label: s.pointsFibreTargetLabel,
                    helper: s.pointsFibreTargetHelper,
                    onChanged: _onFieldChanged,
                    id: 'points-fibre-target',
                  ),
                ]),
                Semantics(
                  identifier: 'points-rebalance-overspend',
                  child: SwitchListTile(
                    title: Text(s.pointsRebalanceTitle),
                    subtitle: Text(s.pointsRebalanceHelp),
                    value: draft.rebalanceOverspend,
                    onChanged: (v) =>
                        _update((d) => d.copyWith(rebalanceOverspend: v)),
                  ),
                ),
                const Divider(),
                _SectionTitle(s.pointsMethodTitle),
                RadioGroup<PointsBudgetMethod>(
                  groupValue: draft.budgetMethod,
                  onChanged: (m) {
                    if (m != null) {
                      _update((d) => d.copyWith(budgetMethod: m));
                    }
                  },
                  child: Column(
                    children: [
                      Semantics(
                        identifier: 'points-method-lean-mass',
                        child: RadioListTile<PointsBudgetMethod>(
                          value: PointsBudgetMethod.leanMass,
                          title: Text(s.pointsMethodLeanMass),
                          subtitle: Text(s.pointsMethodLeanMassSubtitle),
                        ),
                      ),
                      Semantics(
                        identifier: 'points-method-app-macros',
                        child: RadioListTile<PointsBudgetMethod>(
                          value: PointsBudgetMethod.appMacros,
                          title: Text(s.pointsMethodAppMacros),
                          subtitle: Text(s.pointsMethodAppMacrosSubtitle),
                        ),
                      ),
                    ],
                  ),
                ),
                if (draft.budgetMethod == PointsBudgetMethod.leanMass) ...[
                  _fieldRow([
                    _NumberField(
                      controller: _adjustment,
                      label: s.pointsCalorieAdjustmentLabel,
                      helper: s.pointsAutomaticHint,
                      onChanged: _onFieldChanged,
                      id: 'points-adjustment',
                    ),
                    _NumberField(
                      controller: _activity,
                      label: s.pointsActivityLabel,
                      helper: s.pointsAutomaticHint,
                      onChanged: _onFieldChanged,
                      id: 'points-activity',
                    ),
                  ]),
                  _fieldRow([
                    _NumberField(
                      controller: _protein,
                      label: s.pointsProteinPerKgLabel,
                      onChanged: _onFieldChanged,
                      id: 'points-protein-per-kg',
                    ),
                    _NumberField(
                      controller: _carbShare,
                      label: s.pointsCarbShareLabel,
                      onChanged: _onFieldChanged,
                      id: 'points-carb-share',
                    ),
                  ]),
                  const Divider(),
                  _SectionTitle(s.pointsMeasurementsTitle),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Dimens.spacing16,
                    ),
                    child: Text(
                      s.pointsMeasurementsSubtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  _fieldRow([
                    _NumberField(
                      controller: _neck,
                      label: s.pointsNeckLabel,
                      onChanged: _onFieldChanged,
                      id: 'points-neck',
                    ),
                    _NumberField(
                      controller: _waist,
                      label: s.pointsWaistLabel,
                      onChanged: _onFieldChanged,
                      id: 'points-waist',
                    ),
                    _NumberField(
                      controller: _hip,
                      label: s.pointsHipLabel,
                      onChanged: _onFieldChanged,
                      id: 'points-hip',
                    ),
                  ]),
                  if (_suggestion?.bodyFatPercent != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Dimens.spacing16,
                      ),
                      child: Text(
                        s.pointsBodyFatEstimate(
                          PointsFormat.of(
                            context,
                          ).grams(_suggestion!.bodyFatPercent!),
                          PointsFormat.of(
                            context,
                          ).grams(_suggestion!.leanMassKg!),
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _budgetSummary(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final format = PointsFormat.of(context);
    final suggestion = _suggestion;
    if (suggestion == null) return const SizedBox.shrink();
    final r = suggestion.rounded;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${format.points(r.total)} ${s.pointsShort} · '
            '${s.pointsCarbsLabel} ${format.points(r.carbs)} · '
            '${s.pointsProteinLabel} ${format.points(r.protein)} · '
            '${s.pointsFatLabel} ${format.points(r.fat)}',
            style: theme.textTheme.titleMedium,
          ),
          Text(
            s.pointsSuggestedKcal(suggestion.kcalGoal.round().toString()),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Dimens.spacing4),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Dimens.spacing4),
              Expanded(
                child: Text(
                  s.pointsGuideShort,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mealSplit(BuildContext context, PointsSettings draft) {
    final s = S.of(context);
    final format = PointsFormat.of(context);
    final daily = draft.dailyBudgetOverride ?? _suggestion?.rounded;
    if (daily == null) return const SizedBox.shrink();
    final slots = draft.effectiveMealSlots;
    final perSlot = slots.budgets(daily);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(s.pointsMealSplitTitle),
        for (final slot in slots)
          if (perSlot[slot.id] case final budget?)
            ListTile(
              dense: true,
              leading: Icon(mealSlotIcon(slot)),
              title: Text(mealSlotLabel(context, slot)),
              trailing: Text(
                '${format.points(budget.carbs)} / '
                '${format.points(budget.protein)} / '
                '${format.points(budget.fat)}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
        Semantics(
          identifier: 'points-settings-edit-meals',
          child: ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: Text(s.mealSlotsEditButton),
            subtitle: Text(s.mealSlotsEditSubtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MealSlotsScreen()),
              );
              final stored = await _source.getSettings();
              if (!mounted) return;
              final current = _draft;
              if (current == null) return;
              setState(
                () => _draft = current.copyWith(
                  mealSlots: () => stored.mealSlots,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _fieldRow(List<Widget> fields) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Dimens.spacing16,
      Dimens.spacing8,
      Dimens.spacing16,
      0,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(width: Dimens.spacing8),
          Expanded(child: fields[i]),
        ],
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Dimens.spacing16,
      Dimens.spacing16,
      Dimens.spacing16,
      Dimens.spacing8,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final ValueChanged<String> onChanged;
  final String id;

  const _NumberField({
    required this.controller,
    required this.label,
    required this.onChanged,
    required this.id,
    this.helper,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: id,
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}([.,]\d{0,2})?$')),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM),
      ),
    ),
  );
}
