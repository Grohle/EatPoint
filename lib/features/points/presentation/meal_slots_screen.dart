import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/entity/points_settings.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Lets the user set up the meals of their day: add as many as they like,
/// remove, rename and reorder them, and choose each meal's share of the
/// daily points. Every change is saved straight away.
class MealSlotsScreen extends StatefulWidget {
  const MealSlotsScreen({super.key});

  @override
  State<MealSlotsScreen> createState() => _MealSlotsScreenState();
}

class _MealSlotsScreenState extends State<MealSlotsScreen> {
  final _source = locator<PointsSettingsDataSource>();
  PointsSettings? _settings;
  MacroPoints? _daily;

  List<MealSlot> get _slots =>
      _settings?.effectiveMealSlots ?? MealSlot.builtIn();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _source.getSettings();
    MacroPoints? daily;
    if (locator.isRegistered<GetPointsBudgetUsecase>()) {
      try {
        daily = (await locator<GetPointsBudgetUsecase>().getBudget()).daily;
      } catch (_) {
        daily = settings.dailyBudgetOverride;
      }
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _daily = daily;
    });
  }

  Future<void> _saveSlots(List<MealSlot> slots) async {
    final settings = _settings ?? await _source.getSettings();
    final isBuiltIn =
        slots.length == 4 &&
        [
          for (var i = 0; i < 4; i++)
            slots[i] == MealSlot.builtIn(settings.effectiveMealSplit)[i],
        ].every((same) => same);
    final next = settings.copyWith(
      mealSlots: () => isBuiltIn ? null : List.unmodifiable(slots),
    );
    setState(() => _settings = next);
    await _source.saveSettings(next);
  }

  Future<void> _add() async {
    final slot = await showModalBottomSheet<MealSlot>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MealSlotEditor(daily: _daily, all: _slots),
    );
    if (slot == null) return;
    await _saveSlots([..._slots, slot]);
  }

  Future<void> _edit(MealSlot slot) async {
    final edited = await showModalBottomSheet<MealSlot>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MealSlotEditor(daily: _daily, all: _slots, slot: slot),
    );
    if (edited == null) return;
    await _saveSlots([for (final s in _slots) s.id == slot.id ? edited : s]);
  }

  Future<void> _remove(MealSlot slot) async {
    final s = S.of(context);
    if (_slots.length <= 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.mealSlotsLastMeal)));
      return;
    }
    final name = mealSlotLabel(context, slot);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.mealSlotsDeleteTitle(name)),
        content: Text(s.mealSlotsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.dialogCancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.mealSlotsDeleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _saveSlots([
      for (final s in _slots)
        if (s.id != slot.id) s,
    ]);
  }

  Future<void> _reset() async {
    final settings = _settings ?? await _source.getSettings();
    await _saveSlots(MealSlot.builtIn(settings.effectiveMealSplit));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final format = PointsFormat.of(context);
    final slots = _slots;
    final daily = _daily;
    final budgets = daily == null ? null : slots.budgets(daily);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.mealSlotsTitle),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => _reset(),
            itemBuilder: (context) => [
              PopupMenuItem(value: 'reset', child: Text(s.mealSlotsReset)),
            ],
          ),
        ],
      ),
      floatingActionButton: Semantics(
        identifier: 'meal-slots-add',
        child: FloatingActionButton.extended(
          onPressed: _settings == null ? null : _add,
          icon: const Icon(Icons.add_rounded),
          label: Text(s.mealSlotsAddButton),
        ),
      ),
      body: _settings == null
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              header: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.spacing16,
                  Dimens.spacing16,
                  Dimens.spacing16,
                  Dimens.spacing8,
                ),
                child: Text(
                  s.mealSlotsIntro,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              itemCount: slots.length,
              onReorderItem: (from, to) {
                final next = [...slots];
                final moved = next.removeAt(from);
                next.insert(to.clamp(0, next.length), moved);
                _saveSlots(next);
              },
              itemBuilder: (context, i) {
                final slot = slots[i];
                final budget = budgets?[slot.id];
                return Card(
                  key: ValueKey(slot.id),
                  margin: const EdgeInsets.symmetric(
                    horizontal: Dimens.spacing16,
                    vertical: Dimens.spacing4,
                  ),
                  child: ListTile(
                    leading: Icon(mealSlotIcon(slot)),
                    title: Text(mealSlotLabel(context, slot)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: Dimens.spacing4),
                      child: Wrap(
                        spacing: Dimens.spacing4,
                        runSpacing: Dimens.spacing4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (!slot.isBuiltIn)
                            Text(
                              s.mealSlotsStoredAs(
                                mealTypeLabel(context, slot.baseType),
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                          if (budget != null) ...[
                            _MacroPill(
                              label: s.pointsCarbsLabel,
                              value: format.points(budget.carbs),
                              color: palette.carbs,
                            ),
                            _MacroPill(
                              label: s.pointsProteinLabel,
                              value: format.points(budget.protein),
                              color: palette.protein,
                            ),
                            _MacroPill(
                              label: s.pointsFatLabel,
                              value: format.points(budget.fat),
                              color: palette.fat,
                            ),
                          ],
                        ],
                      ),
                    ),
                    onTap: () => _edit(slot),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: s.mealSlotsDeleteConfirm,
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _remove(slot),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(Dimens.spacing8),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Bottom sheet to add a meal or edit one: name, the type it counts as, and
/// its share of each macro's daily points.
class _MealSlotEditor extends StatefulWidget {
  final MacroPoints? daily;
  final List<MealSlot> all;
  final MealSlot? slot;

  const _MealSlotEditor({required this.daily, required this.all, this.slot});

  @override
  State<_MealSlotEditor> createState() => _MealSlotEditorState();
}

class _MealSlotEditorState extends State<_MealSlotEditor> {
  late final TextEditingController _name = TextEditingController();
  late IntakeTypeEntity _type = widget.slot?.baseType ?? IntakeTypeEntity.snack;
  late MacroPoints _share =
      widget.slot?.share ??
      MealSlot.create(name: '', baseType: IntakeTypeEntity.snack).share;
  bool _nameInitialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_nameInitialised) return;
    _nameInitialised = true;
    final slot = widget.slot;
    if (slot != null) _name.text = mealSlotLabel(context, slot);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// This meal's points with its current share, next to the other meals.
  MacroPoints? get _preview {
    final daily = widget.daily;
    if (daily == null) return null;
    const previewId = '__preview__';
    final others = [
      for (final s in widget.all)
        if (s.id != widget.slot?.id) s,
    ];
    final budgets = [
      ...others,
      MealSlot(id: previewId, baseType: _type, share: _share),
    ].budgets(daily);
    return budgets[previewId];
  }

  void _done() {
    final s = S.of(context);
    final typed = _name.text.trim();
    final slot = widget.slot;
    final defaultName = mealTypeLabel(context, _type);
    if (slot == null) {
      Navigator.of(context).pop(
        MealSlot.create(
          name: typed.isEmpty ? s.mealSlotsNewMealName : typed,
          baseType: _type,
          share: _share,
        ),
      );
      return;
    }
    // A built-in meal keeps showing the translated name until the user
    // gives it a different one.
    final keepsBuiltInName =
        slot.isBuiltIn && _type == slot.baseType && typed == defaultName;
    Navigator.of(context).pop(
      slot.copyWith(
        name: () => keepsBuiltInName || typed.isEmpty ? null : typed,
        baseType: _type,
        share: _share,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final format = PointsFormat.of(context);
    final preview = _preview;
    final suggestions = [
      s.mealSlotsSuggestionMidMorning,
      s.mealSlotsSuggestionAfternoon,
      s.mealSlotsSuggestionPreWorkout,
      s.mealSlotsSuggestionPostWorkout,
      s.mealSlotsSuggestionLate,
    ];

    Widget shareSlider(String label, double value, ValueChanged<double> set) =>
        Row(
          children: [
            SizedBox(width: 88, child: Text(label)),
            Expanded(
              child: Slider(
                value: value.clamp(0, 0.6),
                max: 0.6,
                divisions: 24,
                label: '${(value * 100).round()} %',
                onChanged: set,
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${(value * 100).round()} %',
                textAlign: TextAlign.end,
              ),
            ),
          ],
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Dimens.spacing16,
        0,
        Dimens.spacing16,
        MediaQuery.viewInsetsOf(context).bottom + Dimens.spacing16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.slot == null ? s.mealSlotsAddButton : s.mealSlotsEditTitle,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Dimens.spacing16),
            Semantics(
              identifier: 'meal-slot-name',
              child: TextField(
                controller: _name,
                autofocus: widget.slot == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: s.mealSlotsNameLabel,
                  border: const OutlineInputBorder(
                    borderRadius: Dimens.borderRadiusM,
                  ),
                ),
              ),
            ),
            if (widget.slot == null) ...[
              const SizedBox(height: Dimens.spacing8),
              Wrap(
                spacing: Dimens.spacing8,
                children: [
                  for (final name in suggestions)
                    ActionChip(
                      label: Text(name),
                      onPressed: () => setState(() => _name.text = name),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Dimens.spacing16),
            Text(s.mealSlotsCountsAsLabel, style: theme.textTheme.titleSmall),
            const SizedBox(height: Dimens.spacing8),
            SegmentedButton<IntakeTypeEntity>(
              showSelectedIcon: false,
              segments: [
                for (final type in MealSlot.dayOrder)
                  ButtonSegment(
                    value: type,
                    icon: Icon(type.getIconData()),
                    tooltip: mealTypeLabel(context, type),
                  ),
              ],
              selected: {_type},
              onSelectionChanged: (value) =>
                  setState(() => _type = value.first),
            ),
            const SizedBox(height: Dimens.spacing4),
            Text(
              '${mealTypeLabel(context, _type)} · ${s.mealSlotsCountsAsHelper}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            Text(s.mealSlotsShareTitle, style: theme.textTheme.titleSmall),
            shareSlider(
              s.pointsCarbsLabel,
              _share.carbs,
              (v) => setState(
                () => _share = MacroPoints(
                  carbs: v,
                  protein: _share.protein,
                  fat: _share.fat,
                ),
              ),
            ),
            shareSlider(
              s.pointsProteinLabel,
              _share.protein,
              (v) => setState(
                () => _share = MacroPoints(
                  carbs: _share.carbs,
                  protein: v,
                  fat: _share.fat,
                ),
              ),
            ),
            shareSlider(
              s.pointsFatLabel,
              _share.fat,
              (v) => setState(
                () => _share = MacroPoints(
                  carbs: _share.carbs,
                  protein: _share.protein,
                  fat: v,
                ),
              ),
            ),
            if (preview != null)
              Text(
                s.mealSlotsBudgetLine(
                  format.points(preview.carbs),
                  format.points(preview.protein),
                  format.points(preview.fat),
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(
              s.mealSlotsShareHelper,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Dimens.spacing16),
            FilledButton(onPressed: _done, child: Text(s.buttonSaveLabel)),
          ],
        ),
      ),
    );
  }
}

/// One macro's points as a small coloured pill, e.g. "Carbs 2.75".
class _MacroPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MacroPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$label $value',
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}
