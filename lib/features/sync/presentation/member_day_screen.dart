import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/presentation/planned_meal_editor_screen.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_auto_sync.dart';
import 'package:opennutritracker/features/sync/domain/household_menu.dart';
import 'package:opennutritracker/features/sync/presentation/member_avatar.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The meals of a day: the member's own meals, as they shared them, or the
/// four built-in ones; plus any other meal with food that day.
List<MealSlot> memberSlots(MemberSnapshot member, DayPlan? day) {
  final shared = member.profile?.slots ?? const <MemberSlot>[];
  final slots = shared.isNotEmpty
      ? [
          for (final s in shared)
            MealSlot(
              id: s.id,
              baseType: s.baseType,
              share: MacroPoints.zero,
              name: s.name,
            ),
        ]
      : MealSlot.builtIn();
  final known = {for (final s in slots) s.id};
  return [
    ...slots,
    if (day != null)
      for (final id in day.meals.keys)
        if (!known.contains(id) && day.itemsFor(id).isNotEmpty)
          MealSlot(
            id: id,
            baseType: MealSlot.builtIn().first.baseType,
            share: MacroPoints.zero,
            name: id,
          ),
  ];
}

/// Another member's menu for one day. Their meals can be changed here when
/// they allow it; the change reaches their phone on the next sync.
class MemberDayScreen extends StatefulWidget {
  final String memberId;
  final DateTime date;
  final HouseholdStore? store;

  const MemberDayScreen({
    super.key,
    required this.memberId,
    required this.date,
    this.store,
  });

  @override
  State<MemberDayScreen> createState() => _MemberDayScreenState();
}

class _MemberDayScreenState extends State<MemberDayScreen> {
  late final HouseholdStore _store = widget.store ?? locator<HouseholdStore>();
  late DateTime _date = DayPlan.dateOnly(widget.date);

  @override
  void initState() {
    super.initState();
    _store.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    _store.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  MemberSnapshot? get _member => _store
      .otherMembers()
      .where((m) => m.memberId == widget.memberId)
      .firstOrNull;

  Future<void> _edit(MemberSnapshot member, MealSlot slot, DayPlan day) async {
    final locale = Localizations.localeOf(context).toString();
    final profile = member.profile;
    final items = await Navigator.of(context).push<List<PlannedItem>>(
      MaterialPageRoute(
        builder: (_) => PlannedMealEditorScreen(
          title:
              '${member.name} · ${mealSlotLabel(context, slot)} · '
              '${DateFormat.MMMEd(locale).format(_date)}',
          day: _date,
          mealType: slot.baseType,
          items: day.itemsFor(slot.id),
          budget: profile?.budgets[slot.id],
          fibreTarget: profile?.fibre[slot.id] ?? 0,
        ),
      ),
    );
    if (items == null) return;
    await _send(member, slot, items);
  }

  /// Gives [member]'s meal these foods (none to delete it); it reaches
  /// their phone on the next sync.
  Future<void> _send(
    MemberSnapshot member,
    MealSlot slot,
    List<PlannedItem> items,
  ) async {
    await _store.editMemberMenu(
      MenuEdit(
        id: IdGenerator.getUniqueID(),
        memberId: member.memberId,
        date: _date,
        slotId: slot.id,
        items: items,
        by: _store.getHousehold()?.memberName ?? '',
        at: DateTime.now(),
      ),
    );
    HouseholdAutoSync.instance.syncSoon(Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final format = PointsFormat.of(context);
    final member = _member;
    if (member == null) {
      return Scaffold(appBar: AppBar());
    }
    final day = member.dayFor(_date) ?? DayPlan.empty(_date);
    final slots = memberSlots(member, day);
    final canEdit = member.allowsEdits;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            MemberAvatar(name: member.name, colourKey: member.memberId),
            const SizedBox(width: Dimens.spacing8),
            Expanded(
              child: Text(
                s.householdMemberMenu(member.name),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Dimens.spacing16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).previousPageTooltip,
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(
                  () => _date = _date.subtract(const Duration(days: 1)),
                ),
              ),
              Expanded(
                child: Text(
                  toBeginningOfSentenceCase(
                    DateFormat.MMMMEEEEd(locale).format(_date),
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () =>
                    setState(() => _date = _date.add(const Duration(days: 1))),
              ),
            ],
          ),
          if (!canEdit)
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing12),
                child: Text(s.householdMemberNoEdits(member.name)),
              ),
            ),
          for (final slot in slots)
            Card(
              margin: const EdgeInsets.only(top: Dimens.spacing12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.spacing16,
                  Dimens.spacing8,
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
                            mealSlotLabel(context, slot),
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          [
                            format.points(day.pointsFor(slot.id).total),
                            if (member.profile?.budgets[slot.id]
                                case final budget?)
                              format.points(budget.total),
                          ].join(' / '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(' ${s.pointsShort}'),
                        if (day.logged.contains(slot.id))
                          Padding(
                            padding: const EdgeInsets.only(
                              left: Dimens.spacing8,
                            ),
                            child: Chip(
                              avatar: const Icon(Icons.check_rounded, size: 16),
                              label: Text(s.plannerLogged),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                        else if (canEdit) ...[
                          if (day.itemsFor(slot.id).isNotEmpty)
                            Semantics(
                              identifier: 'member-day-delete-${slot.id}',
                              child: IconButton(
                                tooltip: s.plannerDeleteMeal,
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => _send(member, slot, const []),
                              ),
                            ),
                          Semantics(
                            identifier: 'member-day-edit-${slot.id}',
                            child: IconButton(
                              tooltip: s.mealEditorTitle,
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(member, slot, day),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (day.itemsFor(slot.id).isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Dimens.spacing8),
                        child: Text(
                          s.plannerEmptyMeal,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    for (final item in day.itemsFor(slot.id))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(item.name),
                        subtitle: Text(
                          '${format.grams(item.amount)} ${item.unit} · '
                          '${format.points(item.points.total)} ${s.pointsShort}',
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
