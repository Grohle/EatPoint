import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/edit_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/main_appbar.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/diary/diary_page.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/points/data/meal_slot_assignments.dart';
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
import 'package:opennutritracker/features/sync/domain/household_menu.dart';
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

  /// EatPoint household: whose menu opens (a member id); null for the
  /// user's own.
  final String? initialMember;

  /// A meal to scroll to and point out once the day shows.
  final String? initialSlot;

  /// EatPoint: shown as the "My day" tab, joined with the diary: each meal
  /// also lists what was logged outside the menu, the day's activities
  /// follow, and the shopping list lives in the bottom bar instead.
  final bool embedded;

  const PlannerScreen({
    super.key,
    this.initialDay,
    this.initialMember,
    this.initialSlot,
    this.embedded = false,
  });

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

  /// The user's own meals, in the order of a day.
  List<MealSlot> get _mySlots =>
      _budget?.slots.isNotEmpty == true ? _budget!.slots : MealSlot.builtIn();

  /// The meals of the menu on screen: the user's, or the member's.
  List<MealSlot> get _slots {
    final member = _viewed;
    return member == null ? _mySlots : memberSlots(member, null);
  }

  /// The meals plus, for the selected day, any meal planned earlier
  /// that has since been removed, so its food stays visible.
  List<MealSlot> _slotsFor(DayPlan day) {
    final member = _viewed;
    if (member != null) return memberSlots(member, day);
    return [
      ..._slots,
      // EatPoint: with what was logged too, on My day.
      for (final id in {...day.meals.keys, ..._diary.keys})
        if (_slots.byId(id) == null &&
            (day.itemsFor(id).isNotEmpty || (_diary[id]?.isNotEmpty ?? false)))
          MealSlot(
            id: id,
            baseType:
                MealSlot.dayOrder.where((t) => t.name == id).firstOrNull ??
                MealSlot.dayOrder.last,
            share: MacroPoints.zero,
          ),
    ];
  }

  DateTime get _weekStart => DayPlan.weekStart(_selected);

  /// EatPoint household: the other members, whose menus can be shown
  /// (and changed, when they allow it) in place of the user's.
  final HouseholdStore? _household = locator.isRegistered<HouseholdStore>()
      ? locator<HouseholdStore>()
      : null;
  List<MemberSnapshot> _others = const [];

  /// Whose menu shows: null for the user's own, else a member id.
  late String? _viewing = widget.initialMember;

  /// The meal to scroll to once it is on screen, and the one pointed out.
  late String? _scrollTo = widget.initialSlot;
  String? _highlight;
  final _slotKeys = <String, GlobalKey>{};

  /// EatPoint (My day): the diary's entries of the selected day by meal,
  /// and its activities.
  Map<String, List<IntakeEntity>> _diary = const {};
  List<UserActivityEntity> _activities = const [];
  StreamSubscription<Object?>? _diaryWatch;
  int _diaryTicket = 0;
  bool _imperial = false;

  /// When the user's day starts (#139), as the diary reads it.
  int _offsetHours = 0;
  int _offsetMinutes = 0;

  /// What the diary has for [slot] that the menu didn't put there.
  List<IntakeEntity> _diaryExtra(DayPlan day, MealSlot slot) {
    final fromMenu = day.loggedIntakes[slot.id] ?? const <String>[];
    return [
      for (final i in _diary[slot.id] ?? const <IntakeEntity>[])
        if (!fromMenu.contains(i.id)) i,
    ];
  }

  static MacroPoints _intakePoints(IntakeEntity i) => MacroPoints(
    carbs: i.totalCarbsGram * 4 / 100,
    protein: i.totalProteinsGram * 4 / 100,
    fat: i.totalFatsGram * 9 / 100,
  );

  Future<void> _loadDiary() async {
    if (!widget.embedded || !locator.isRegistered<IntakeRepository>()) return;
    final date = _selected;
    final ticket = ++_diaryTicket;
    final repo = locator<IntakeRepository>();
    final intakes = <IntakeEntity>[
      for (final type in IntakeTypeEntity.values)
        ...await repo.getIntakeByDateAndType(
          type,
          date,
          dayStartOffsetHours: _offsetHours,
          dayStartOffsetMinutes: _offsetMinutes,
        ),
    ];
    final activities = locator.isRegistered<GetUserActivityUsecase>()
        ? await locator<GetUserActivityUsecase>().getUserActivityByDay(
            date,
            dayStartOffsetHours: _offsetHours,
            dayStartOffsetMinutes: _offsetMinutes,
          )
        : const <UserActivityEntity>[];
    if (!mounted || ticket != _diaryTicket) return;
    final slots = _mySlots;
    final bySlot = <String, List<IntakeEntity>>{};
    void put(String id, IntakeEntity i) =>
        bySlot.putIfAbsent(id, () => []).add(i);
    String slotFor(IntakeTypeEntity type) =>
        slots.where((s) => s.baseType == type).firstOrNull?.id ?? type.name;
    if (locator.isRegistered<MealSlotAssignments>()) {
      final grouping = locator<MealSlotAssignments>().group(intakes, slots);
      for (final e in grouping.bySlot.entries) {
        for (final i in e.value) {
          put(e.key, i);
        }
      }
      for (final e in grouping.orphans.entries) {
        for (final i in e.value) {
          put(slotFor(e.key), i);
        }
      }
    } else {
      for (final i in intakes) {
        put(slotFor(i.type), i);
      }
    }
    setState(() {
      _diary = bySlot;
      _activities = activities;
    });
  }

  Future<void> _afterDiaryChange() async {
    PlannedMealLogger.refreshDiary();
    await _loadDiary();
  }

  Future<void> _editIntake(IntakeEntity intake) async {
    final day = _selected;
    final amount = await showDialog<double>(
      context: context,
      builder: (context) =>
          EditDialog(intakeEntity: intake, usesImperialUnits: _imperial),
    );
    if (amount == null) return;
    await locator<CalendarDayBloc>().updateIntakeItem(intake.id, {
      'amount': amount,
    }, day);
    await _afterDiaryChange();
  }

  Future<bool> _confirmDeleteEntry(String name) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.myDayRemoveEntry(name)),
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

  Future<void> _deleteIntake(IntakeEntity intake) async {
    final day = _selected;
    setState(() {
      _diary = {
        for (final e in _diary.entries)
          e.key: [
            for (final i in e.value)
              if (i.id != intake.id) i,
          ],
      };
    });
    await locator<CalendarDayBloc>().deleteIntakeItem(context, intake, day);
    await _afterDiaryChange();
  }

  Future<void> _deleteActivity(UserActivityEntity activity) async {
    final day = _selected;
    setState(() {
      _activities = [
        for (final a in _activities)
          if (a.id != activity.id) a,
      ];
    });
    await locator<CalendarDayBloc>().deleteUserActivityItem(
      context,
      activity,
      day,
    );
    await _afterDiaryChange();
  }

  /// Logs a food straight into the diary for [slot] on the selected day.
  Future<void> _logMore(MealSlot slot) async {
    MealSlotContext.select(slot);
    await Navigator.of(context).pushNamed(
      NavigationOptions.addMealRoute,
      arguments: AddMealScreenArguments(
        AddMealExtension.fromIntakeTypeEntity(slot.baseType),
        _selected,
      ),
    );
    await _loadDiary();
  }

  void _openFullDiary() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: MainAppbar(
          title: S.of(context).diaryLabel,
          iconData: Icons.book,
        ),
        body: const DiaryPage(),
      ),
    ),
  );

  MemberSnapshot? get _viewed => _viewing == null
      ? null
      : _others.where((m) => m.memberId == _viewing).firstOrNull;

  /// Whether the menu on screen can be changed here.
  bool get _canEdit => _viewed?.allowsEdits ?? true;

  /// The colour of whoever's menu shows; null outside a household.
  Color? get _accent {
    final id = _viewed?.memberId ?? _household?.getHousehold()?.memberId;
    return id == null ? null : memberColor(id);
  }

  MacroPoints? _slotBudget(String id) {
    final member = _viewed;
    return member == null ? _budget?.perSlot[id] : member.profile?.budgets[id];
  }

  double _slotFibre(String id) {
    final member = _viewed;
    return member == null
        ? _budget?.fibrePerSlot[id] ?? 0
        : member.profile?.fibre[id] ?? 0;
  }

  /// The day's points: the user's budget, or the sum of the member's meals.
  MacroPoints? get _dailyBudget {
    final member = _viewed;
    if (member == null) return _budget?.daily;
    final budgets = member.profile?.budgets.values ?? const <MacroPoints>[];
    if (budgets.isEmpty) return null;
    return budgets.fold<MacroPoints>(MacroPoints.zero, (a, b) => a + b);
  }

  double get _dailyFibre {
    final member = _viewed;
    if (member == null) return _budget?.fibreDaily ?? 0;
    return (member.profile?.fibre.values ?? const <double>[]).fold(
      0.0,
      (a, b) => a + b,
    );
  }

  @override
  void initState() {
    super.initState();
    _source.revision.addListener(_reload);
    _household?.revision.addListener(_reload);
    HouseholdAutoSync.instance.attach();
    _reload();
    _loadBudget();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSlot());
    if (widget.embedded && locator.isRegistered<CalendarDayBloc>()) {
      // Anything logged elsewhere (the + button, the full diary) shows here.
      _diaryWatch = locator<CalendarDayBloc>().stream.listen(
        (_) => _loadDiary(),
      );
    }
    if (widget.embedded && locator.isRegistered<GetConfigUsecase>()) {
      locator<GetConfigUsecase>().getConfig().then((c) {
        if (!mounted) return;
        _imperial = c.usesImperialFoodUnits;
        _offsetHours = c.dayStartOffsetHours;
        _offsetMinutes = c.dayStartOffsetMinutes;
        _loadDiary();
      });
    }
  }

  /// Brings the meal asked for into view and points it out for a moment.
  void _scrollToSlot() {
    final id = _scrollTo;
    if (id == null || !mounted) return;
    final target = _slotKeys[id]?.currentContext;
    if (target == null) return;
    _scrollTo = null;
    setState(() => _highlight = id);
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      alignment: 0.1,
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlight == id) setState(() => _highlight = null);
    });
  }

  @override
  void dispose() {
    _source.revision.removeListener(_reload);
    _household?.revision.removeListener(_reload);
    _diaryWatch?.cancel();
    HouseholdAutoSync.instance.detach();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _others = _household?.getHousehold() == null
          ? const []
          : _household!.otherMembers();
      final member = _viewed;
      _week = member == null
          ? _source.getWeek(_selected)
          : [
              for (var i = 0; i < 7; i++)
                member.dayFor(_weekStart.add(Duration(days: i))) ??
                    DayPlan.empty(_weekStart.add(Duration(days: i))),
            ];
    });
    _loadDiary();
  }

  /// Copies a food of a member's menu into the same meal of the user's.
  Future<void> _copyToMine(MealSlot slot, PlannedItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = S.of(context).plannerCopied;
    final mine = _source.getDay(_selected);
    final target =
        _mySlots.byId(slot.id) ??
        _mySlots.where((s) => s.baseType == slot.baseType).firstOrNull ??
        slot;
    await _source.saveDay(
      mine.withMeal(target.id, [
        ...mine.itemsFor(target.id),
        PlannedItem(
          id: IdGenerator.getUniqueID(),
          meal: item.meal,
          amount: item.amount,
          unit: item.unit,
        ),
      ]),
    );
    await _rescheduleReminders();
    messenger.showSnackBar(SnackBar(content: Text(copied)));
  }

  /// Picks whose menu shows: the user's or another member's.
  Future<void> _pickMember() async {
    final household = _household?.getHousehold();
    if (household == null) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final s = S.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.spacing16,
                  0,
                  Dimens.spacing16,
                  Dimens.spacing8,
                ),
                child: Text(
                  s.plannerWhoseMenu,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Semantics(
                identifier: 'planner-view-me',
                child: ListTile(
                  leading: MemberAvatar(
                    name: household.memberName,
                    colourKey: household.memberId,
                    radius: 16,
                  ),
                  title: Text(s.householdYou(household.memberName)),
                  selected: _viewed == null,
                  trailing: _viewed == null
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(''),
                ),
              ),
              for (final m in _others)
                Semantics(
                  identifier: 'planner-view-${m.memberId}',
                  child: ListTile(
                    leading: MemberAvatar(
                      name: m.name,
                      colourKey: m.memberId,
                      radius: 16,
                    ),
                    title: Text(m.name),
                    subtitle: m.allowsEdits ? null : Text(s.plannerReadOnly),
                    selected: _viewed?.memberId == m.memberId,
                    trailing: _viewed?.memberId == m.memberId
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.of(context).pop(m.memberId),
                  ),
                ),
              const SizedBox(height: Dimens.spacing8),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _viewing = picked.isEmpty ? null : picked);
    _reload();
  }

  Future<void> _loadBudget() async {
    try {
      final budget = await locator<GetPointsBudgetUsecase>().getBudget();
      if (mounted) setState(() => _budget = budget);
      // The user's own meals may only be known now.
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSlot());
    } catch (_) {}
  }

  DayPlan get _day => _week.firstWhere(
    (d) => d.date == _selected,
    orElse: () => DayPlan.empty(_selected),
  );

  /// Saves a day of the menu on screen.
  Future<void> _save(DayPlan plan) => _saveFor(_viewed?.memberId, plan);

  /// Saves a day of [memberId]'s menu (null: the user's). A member's
  /// changed meals go to their phone as edits, on the next sync.
  Future<void> _saveFor(String? memberId, DayPlan plan) async {
    if (memberId == null) {
      await _source.saveDay(plan);
      await _rescheduleReminders();
      return;
    }
    final store = _household;
    final member = store
        ?.otherMembers()
        .where((m) => m.memberId == memberId)
        .firstOrNull;
    if (store == null || member == null) return;
    final before = member.dayFor(plan.date) ?? DayPlan.empty(plan.date);
    final by = store.getHousehold()?.memberName ?? '';
    var sent = false;
    for (final id in {...before.meals.keys, ...plan.meals.keys}) {
      final items = plan.itemsFor(id);
      if (_sameItems(before.itemsFor(id), items)) continue;
      await store.editMemberMenu(
        MenuEdit(
          id: IdGenerator.getUniqueID(),
          memberId: memberId,
          date: plan.date,
          slotId: id,
          items: items,
          by: by,
          at: DateTime.now(),
        ),
      );
      sent = true;
    }
    if (sent) HouseholdAutoSync.instance.syncSoon(Duration.zero);
  }

  static bool _sameItems(List<PlannedItem> a, List<PlannedItem> b) =>
      jsonEncode([for (final i in a) i.toJson()]) ==
      jsonEncode([for (final i in b) i.toJson()]);

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
      slots: _mySlots,
      upcoming: [
        for (var i = 0; i < 7; i++)
          _source.getDay(today.add(Duration(days: i))),
      ],
      texts: plannerReminderTextsOf(context),
    );
  }

  Future<void> _openCalendar() async {
    final picked = await Navigator.of(context).push<PlannerCalendarPick>(
      MaterialPageRoute(
        builder: (_) => PlannerCalendarScreen(initialDay: _selected),
      ),
    );
    // Days may have been deleted, planned or copied there.
    await _rescheduleReminders();
    if (picked == null || !mounted) return;
    setState(() {
      _selected = DayPlan.dateOnly(picked.date);
      // A meal tapped there opens in its owner's menu, pointed out.
      if (picked.slotId != null) {
        _viewing = picked.memberId;
        _scrollTo = picked.slotId;
      }
    });
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSlot());
  }

  void _moveWeek(int weeks) {
    setState(() => _selected = _selected.add(Duration(days: 7 * weeks)));
    _reload();
  }

  Future<void> _addDish(MealSlot slot) async {
    final budget = _slotBudget(slot.id);
    final remaining = budget == null ? null : budget - _day.pointsFor(slot.id);
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

  /// Asks before a food swiped away leaves its meal.
  Future<bool> _confirmRemoveItem(PlannedItem item) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.plannerRemoveItemTitle(item.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.plannerRemoveItem),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// A food swiped away: gone from the screen at once, then saved.
  void _removeSwiped(MealSlot slot, PlannedItem item) {
    final day = _day;
    final next = day.withMeal(
      slot.id,
      day.itemsFor(slot.id).where((i) => i.id != item.id).toList(),
    );
    setState(() {
      _week = [for (final d in _week) d.date == next.date ? next : d];
    });
    _save(next);
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
      final logged = await PlannedMealLogger.app(
        context,
      ).log(day, slot, PlannedMealLogger.appAdd(context, bloc, slot, day.date));
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
    final member = _viewed;
    final target = member?.memberId;
    // Only the user's own diary is touched here.
    final wasLogged = member == null && day.logged.contains(slot.id);
    final edited = await Navigator.of(context).push<List<PlannedItem>>(
      MaterialPageRoute(
        builder: (_) => PlannedMealEditorScreen(
          title:
              '${member == null ? '' : '${member.name} · '}'
              '${mealSlotLabel(context, slot)} · '
              '${DateFormat.MMMEd(locale).format(day.date)}',
          day: day.date,
          mealType: slot.baseType,
          items: day.itemsFor(slot.id),
          budget: _slotBudget(slot.id),
          fibreTarget: _slotFibre(slot.id),
          logged: wasLogged,
        ),
      ),
    );
    if (edited == null || !mounted) return;
    if (!wasLogged) {
      await _saveFor(target, day.withMeal(slot.id, edited));
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

  /// EatPoint: takes one meal out of the day's menu (and so out of the
  /// shopping list). A logged meal asks whether its diary entries go too.
  /// Can be undone from the snack bar.
  /// [ask]: confirm first, as after a swipe (a logged meal always asks).
  Future<void> _deleteMeal(MealSlot slot, {bool ask = false}) async {
    final s = S.of(context);
    final before = _day;
    final target = _viewed?.memberId;
    if (before.itemsFor(slot.id).isEmpty) return;
    final mealName = mealSlotLabel(context, slot);
    var alsoDiary = false;
    if (target == null && before.logged.contains(slot.id)) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.plannerDeleteLoggedTitle(mealName)),
          content: Text(s.plannerDeleteLoggedBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(s.plannerDeleteOnlyMenu),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(s.plannerDeleteAlsoDiary),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      alsoDiary = choice;
    } else if (ask) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.plannerConfirmDeleteMeal(mealName)),
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
      if (ok != true || !mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    var next = before;
    if (alsoDiary) {
      next = await PlannedMealLogger.app(context).unlog(next, slot);
      PlannedMealLogger.refreshDiary();
    }
    await _saveFor(
      target,
      next.withMeal(slot.id, const []).withLogged(slot.id, false),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.plannerDeletedMeal(mealName)),
        // Goes away on its own, like any other message.
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: s.plannerUndo,
          // What the diary lost is not put back: the meal returns as
          // planned, ready to log again.
          onPressed: () => _saveFor(
            target,
            alsoDiary ? before.withLogged(slot.id, false) : before,
          ),
        ),
      ),
    );
  }

  /// EatPoint: empties the selected day's menu after asking, optionally
  /// taking what was logged from it out of the diary too.
  Future<void> _deleteDay() async {
    final s = S.of(context);
    final before = _day;
    if (before.isEmpty) return;
    final locale = Localizations.localeOf(context).toString();
    final target = _viewed?.memberId;
    final hasLogged = target == null && before.logged.isNotEmpty;
    var alsoDiary = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            s.plannerDeleteDayTitle(
              DateFormat.MMMMEEEEd(locale).format(before.date),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.plannerDeleteDayBody),
              if (hasLogged)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: alsoDiary,
                  title: Text(s.plannerDeleteDayDiary),
                  onChanged: (v) => setDialogState(() => alsoDiary = v!),
                ),
            ],
          ),
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
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    var restore = before;
    if (alsoDiary) {
      final logger = PlannedMealLogger.app(context);
      var day = before;
      for (final id in before.logged) {
        final slot = _slotsFor(before).where((s) => s.id == id).firstOrNull;
        if (slot == null) continue;
        day = await logger.unlog(day, slot);
      }
      restore = day;
      PlannedMealLogger.refreshDiary();
    }
    await _saveFor(target, DayPlan.empty(before.date));
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.plannerDeletedDay),
        // Goes away on its own, like any other message.
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: s.plannerUndo,
          onPressed: () => _saveFor(target, restore),
        ),
      ),
    );
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
        await _deleteDay();
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
    final member = _viewed;
    final household = _household?.getHousehold();
    final daily = _dailyBudget;
    final dailyFibre = _dailyFibre;
    final myWeek = member == null ? _week : _source.getWeek(_selected);
    final shoppingCount = ShoppingListBuilder.build([
      for (final d in myWeek) (owner: 'me', plan: d),
    ]).length;
    // EatPoint: the menu takes the colour of whoever it belongs to.
    final base = Theme.of(context);
    final accent = _accent;
    final themed = accent == null
        ? base
        : base.copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: accent,
              brightness: base.brightness,
            ),
          );

    return Theme(
      data: themed,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member == null
                      ? s.plannerTitle
                      : s.householdMemberMenu(member.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(range, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            actions: [
              if (household != null && _others.isNotEmpty)
                Semantics(
                  identifier: 'planner-viewing',
                  button: true,
                  label: s.plannerWhoseMenu,
                  child: IconButton(
                    onPressed: _pickMember,
                    icon: MemberAvatar(
                      name: member?.name ?? household.memberName,
                      colourKey: member?.memberId ?? household.memberId,
                      radius: 14,
                    ),
                  ),
                ),
              if (widget.embedded)
                Semantics(
                  identifier: 'my-day-full-diary',
                  child: IconButton(
                    tooltip: s.myDayFullDiary,
                    onPressed: _openFullDiary,
                    icon: const Icon(Icons.menu_book_outlined),
                  ),
                ),
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
                  // Another member's menu: only what changes that menu.
                  itemBuilder: (context) => member != null
                      ? [
                          if (_canEdit)
                            PopupMenuItem(
                              value: _DayAction.clearDay,
                              enabled: !day.isEmpty,
                              child: Text(s.plannerClearDay),
                            ),
                          PopupMenuItem(
                            value: _DayAction.shareWeek,
                            child: Text(s.plannerShareWeek),
                          ),
                        ]
                      : [
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
                  // On My day, room below for the + button.
                  padding: EdgeInsets.fromLTRB(
                    Dimens.spacing16,
                    0,
                    Dimens.spacing16,
                    widget.embedded ? 96 : Dimens.spacing16,
                  ),
                  children: [
                    if (member != null && !member.allowsEdits)
                      Padding(
                        padding: const EdgeInsets.only(top: Dimens.spacing8),
                        child: Card(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(Dimens.spacing12),
                            child: Text(s.householdMemberNoEdits(member.name)),
                          ),
                        ),
                      ),
                    WeekInsightsCard(
                      week: _week,
                      fibreTargetPoints: dailyFibre > 0 ? dailyFibre : 5,
                    ),
                    if (daily != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: Dimens.spacing8,
                        ),
                        child: Text(
                          [
                            s.plannerDayPoints(
                              format.points(day.totalPoints.total),
                              format.points(daily.total),
                            ),
                            if (dailyFibre > 0)
                              s.plannerDayFibre(
                                format.points(day.totalFibre),
                                format.points(dailyFibre),
                              ),
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    for (final slot in _slotsFor(day))
                      _mealCard(context, day, slot),
                    if (widget.embedded &&
                        member == null &&
                        _activities.isNotEmpty)
                      _activitiesCard(context),
                    if (!day.isEmpty && _canEdit)
                      Align(
                        alignment: Alignment.center,
                        child: Semantics(
                          identifier: 'planner-delete-day',
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                            onPressed: _deleteDay,
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: Text(s.plannerClearDay),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // On My day the shopping list is in the bottom bar.
              if (!widget.embedded)
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
                            minimumSize: const Size.fromHeight(
                              Dimens.minTouchTarget,
                            ),
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ShoppingListScreen(weekOf: _weekStart),
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
        ),
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
                          onTap: () {
                            setState(() => _selected = date);
                            _loadDiary();
                          },
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

  /// The red strip a card or row shows as it is swiped left to delete.
  Widget _swipeBackground(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: Dimens.borderRadiusM,
      ),
      child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
    );
  }

  Widget _mealCard(BuildContext context, DayPlan day, MealSlot slot) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final format = PointsFormat.of(context);
    final items = day.itemsFor(slot.id);
    final mine = _viewed == null;
    // EatPoint (My day): what the diary has beyond the menu counts too.
    final extra = widget.embedded && mine
        ? _diaryExtra(day, slot)
        : const <IntakeEntity>[];
    final points = extra.fold(
      day.pointsFor(slot.id),
      (sum, i) => sum + _intakePoints(i),
    );
    final mealBudget = _slotBudget(slot.id);
    final logged = day.logged.contains(slot.id);
    final over = mealBudget != null && points.total > mealBudget.total + 0.001;
    final canEdit = _canEdit;
    final busy = _logging.contains(slot.id);
    final highlighted = _highlight == slot.id;
    final card = Card(
      margin: const EdgeInsets.only(bottom: Dimens.spacing12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlighted
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
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
                Icon(
                  mealSlotIcon(slot),
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: Dimens.spacing8),
                // The points under the name, so the meal's buttons fit.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _slotName(context, slot),
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        mealBudget == null
                            ? '${format.points(points.total)} ${s.pointsShort}'
                            : '${format.points(points.total)} / '
                                  '${format.points(mealBudget.total)} ${s.pointsShort}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: over ? theme.colorScheme.error : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (items.isNotEmpty && canEdit)
                  Semantics(
                    identifier: 'planner-delete-${slot.id}',
                    child: IconButton(
                      tooltip: s.plannerDeleteMeal,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: busy ? null : () => _deleteMeal(slot),
                    ),
                  ),
                if (canEdit)
                  Semantics(
                    identifier: 'planner-edit-${slot.id}',
                    child: IconButton(
                      tooltip: s.mealEditorTitle,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: busy ? null : () => _editMeal(slot),
                    ),
                  ),
                // Logging is for the user's own diary only.
                if (!mine && logged)
                  Tooltip(
                    message: s.plannerLogged,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  )
                else if (mine && logged)
                  Semantics(
                    identifier: 'planner-unlog-${slot.id}',
                    child: ActionChip(
                      avatar: const Icon(Icons.check_rounded, size: 16),
                      label: Text(s.plannerLogged),
                      tooltip: s.plannerUnlog,
                      visualDensity: VisualDensity.compact,
                      onPressed: busy ? null : () => _unlogMeal(slot),
                    ),
                  )
                else if (mine && items.isNotEmpty)
                  Semantics(
                    identifier: 'planner-log-${slot.id}',
                    child: OutlinedButton(
                      onPressed: busy ? null : () => _logMeal(slot),
                      child: busy
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
            if (items.isEmpty && extra.isEmpty)
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
              Dismissible(
                key: ValueKey('planner-item-${item.id}'),
                direction: canEdit && !logged
                    ? DismissDirection.endToStart
                    : DismissDirection.none,
                background: _swipeBackground(context),
                confirmDismiss: (_) => _confirmRemoveItem(item),
                onDismissed: (_) => _removeSwiped(slot, item),
                child: ListTile(
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
                            if (PortionFormatter.forFood(
                                  item.name,
                                  item.amount,
                                  code: item.meal.code,
                                )
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
                  trailing: !mine
                      // Someone else's food can be copied to the user's menu.
                      ? IconButton(
                          tooltip: s.plannerCopyToMine,
                          icon: const Icon(Icons.content_copy_rounded),
                          onPressed: () => _copyToMine(slot, item),
                        )
                      : logged
                      ? null
                      : IconButton(
                          tooltip: s.plannerRemoveItem,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => _removeItem(slot, item),
                        ),
                ),
              ),
            if (extra.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: Dimens.spacing4),
                child: Text(
                  s.myDayLogged,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              for (final intake in extra) _diaryRow(context, intake),
            ],
            Wrap(
              spacing: Dimens.spacing4,
              children: [
                if (!logged && canEdit)
                  Semantics(
                    identifier: 'planner-add-${slot.id}',
                    child: TextButton.icon(
                      onPressed: () => _addDish(slot),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(s.plannerAddDish),
                    ),
                  ),
                // Straight into the diary, today or before.
                if (widget.embedded &&
                    mine &&
                    !_selected.isAfter(DayPlan.dateOnly(DateTime.now())))
                  Semantics(
                    identifier: 'my-day-log-more-${slot.id}',
                    child: TextButton.icon(
                      onPressed: () => _logMore(slot),
                      icon: const Icon(Icons.playlist_add_check_rounded),
                      label: Text(s.myDayLogMore),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    // Swipe a meal left to delete it; the card stays, empty.
    return KeyedSubtree(
      key: _slotKeys.putIfAbsent(slot.id, GlobalKey.new),
      child: Dismissible(
        key: ValueKey('planner-meal-${day.date}-${slot.id}'),
        direction: items.isNotEmpty && canEdit && !busy
            ? DismissDirection.endToStart
            : DismissDirection.none,
        background: Padding(
          padding: const EdgeInsets.only(bottom: Dimens.spacing12),
          child: _swipeBackground(context),
        ),
        confirmDismiss: (_) async {
          await _deleteMeal(slot, ask: true);
          return false;
        },
        child: card,
      ),
    );
  }
}

extension on _PlannerScreenState {
  /// One diary entry on My day: tap to change the amount, swipe left to
  /// delete it after asking.
  Widget _diaryRow(BuildContext context, IntakeEntity intake) {
    final s = S.of(context);
    final format = PointsFormat.of(context);
    final scheme = Theme.of(context).colorScheme;
    final name = intake.meal.name ?? '';
    return Dismissible(
      key: ValueKey('my-day-intake-${intake.id}'),
      direction: DismissDirection.endToStart,
      background: _swipeBackground(context),
      confirmDismiss: (_) => _confirmDeleteEntry(name),
      onDismissed: (_) => _deleteIntake(intake),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        onTap: () => _editIntake(intake),
        leading: Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: scheme.primary,
        ),
        minLeadingWidth: 20,
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${format.grams(intake.amount)} ${intake.unit} · '
          '${format.points(_PlannerScreenState._intakePoints(intake).total)} '
          '${s.pointsShort}',
        ),
      ),
    );
  }

  /// The day's activities, each swipeable away.
  Widget _activitiesCard(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
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
                Icon(
                  Icons.directions_run_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: Dimens.spacing8),
                Text(s.myDayActivities, style: theme.textTheme.titleSmall),
              ],
            ),
            for (final a in _activities)
              Dismissible(
                key: ValueKey('my-day-activity-${a.id}'),
                direction: DismissDirection.endToStart,
                background: _swipeBackground(context),
                confirmDismiss: (_) => _confirmDeleteEntry(
                  a.physicalActivityEntity.getName(context),
                ),
                onDismissed: (_) => _deleteActivity(a),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(a.physicalActivityEntity.getName(context)),
                  subtitle: Text(
                    '${a.duration.round()} min · '
                    '${(a.userKcal ?? a.burnedKcal).round()} kcal',
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
