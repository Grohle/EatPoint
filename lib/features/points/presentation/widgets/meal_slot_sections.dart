import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/points/data/meal_slot_assignments.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/presentation/meal_slots_screen.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// One meal section to draw: one of the user's meals, or the foods of a meal
/// type the user no longer has a meal for.
class MealSlotSection {
  /// Stable key for the section.
  final String key;
  final String title;
  final IconData icon;
  final IntakeTypeEntity type;
  final List<IntakeEntity> intakes;

  /// Null for the foods of a type with no meal.
  final MealSlot? slot;

  const MealSlotSection({
    required this.key,
    required this.title,
    required this.icon,
    required this.type,
    required this.intakes,
    this.slot,
  });

  AddMealType get addMealType => AddMealExtension.fromIntakeTypeEntity(type);
}

/// The meal sections of a day, one per meal the user has set up, instead of
/// the four fixed ones.
///
/// [buildSection] draws one section (Home and the Diary pass their own
/// list widget). Touching a section selects its meal, so food added from it
/// is remembered under that meal. Ends with a button to edit the meals.
class MealSlotSections extends StatefulWidget {
  final List<IntakeEntity> intakes;
  final Widget Function(BuildContext context, MealSlotSection section)
  buildSection;

  const MealSlotSections({
    super.key,
    required this.intakes,
    required this.buildSection,
  });

  /// Whether EatPoint's meals replace the four fixed sections.
  static bool get enabled =>
      locator.isRegistered<PointsSettingsDataSource>() &&
      locator.isRegistered<MealSlotAssignments>();

  @override
  State<MealSlotSections> createState() => _MealSlotSectionsState();
}

class _MealSlotSectionsState extends State<MealSlotSections> {
  final _settings = locator<PointsSettingsDataSource>();
  final _assignments = locator<MealSlotAssignments>();
  List<MealSlot> _slots = MealSlot.builtIn();

  @override
  void initState() {
    super.initState();
    _settings.revision.addListener(_load);
    _assignments.revision.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _settings.revision.removeListener(_load);
    _assignments.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final settings = await _settings.getSettings();
    if (!mounted) return;
    setState(() => _slots = settings.effectiveMealSlots);
  }

  List<MealSlotSection> _sections(BuildContext context) {
    final grouping = _assignments.group(widget.intakes, _slots);
    return [
      for (final slot in _slots)
        MealSlotSection(
          key: slot.id,
          title: mealSlotLabel(context, slot),
          icon: mealSlotIcon(slot),
          type: slot.baseType,
          intakes: grouping.bySlot[slot.id] ?? const [],
          slot: slot,
        ),
      for (final e in grouping.orphans.entries)
        MealSlotSection(
          key: 'orphan-${e.key.name}',
          title: mealTypeLabel(context, e.key),
          icon: e.key.getIconData(),
          type: e.key,
          intakes: e.value,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections)
          Listener(
            key: ValueKey('meal-slot-${section.key}'),
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              final slot = section.slot;
              if (slot != null) {
                MealSlotContext.select(slot);
              } else {
                MealSlotContext.clear();
              }
            },
            child: widget.buildSection(context, section),
          ),
        Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.only(top: Dimens.spacing8),
            child: Semantics(
              identifier: 'meal-slots-edit',
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MealSlotsScreen()),
                ),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(S.of(context).mealSlotsEditButton),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
