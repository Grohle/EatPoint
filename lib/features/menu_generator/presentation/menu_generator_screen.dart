import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diet_profile/data/diet_profile_store.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_profile_screen.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_text.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/label_scan/data/remote_nutrition_extractor.dart';
import 'package:opennutritracker/features/menu_generator/data/fixed_foods_store.dart';
import 'package:opennutritracker/features/menu_generator/data/menu_generator_sources.dart';
import 'package:opennutritracker/features/planner/presentation/dish_picker_screen.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/features/menu_import/data/menu_food_matcher.dart';
import 'package:opennutritracker/features/menu_import/data/remote_menu_extractor.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';
import 'package:opennutritracker/features/menu_import/presentation/menu_import_review_screen.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/points/domain/entity/meal_slot.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/menu_generator/domain/member_menu_adapter.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_auto_sync.dart';
import 'package:opennutritracker/features/sync/domain/household_menu.dart';
import 'package:opennutritracker/features/sync/presentation/member_avatar.dart';
import 'package:opennutritracker/features/sync/presentation/member_day_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

enum _Engine { phone, ai }

/// Generates a menu for the user's meals, on the phone or with their AI
/// provider, following their diet; the result goes through the importer's
/// review before anything is saved. Pops with the number of days saved.
class MenuGeneratorScreen extends StatefulWidget {
  /// The first day to plan; today when null.
  final DateTime? initialDay;

  /// How many days to plan from it, as days chosen in the calendar.
  final int? initialDays;

  const MenuGeneratorScreen({super.key, this.initialDay, this.initialDays});

  @override
  State<MenuGeneratorScreen> createState() => _MenuGeneratorScreenState();
}

class _MenuGeneratorScreenState extends State<MenuGeneratorScreen> {
  static const _standardCounts = [1, 3, 5, 7, 14];

  /// The usual choices, plus the number of days chosen in the calendar.
  late final List<int> _dayCounts = {
    ..._standardCounts,
    ?widget.initialDays,
  }.toList()..sort();

  late DateTime _start = DayPlan.dateOnly(widget.initialDay ?? DateTime.now());
  late int _days = widget.initialDays ?? 7;
  bool _preferOwn = true;
  _Engine _engine = _Engine.phone;
  bool _aiAvailable = false;
  bool _busy = false;
  String? _error;
  int _seed = DateTime.now().millisecondsSinceEpoch % 100000;
  List<MealSlot> _slots = MealSlot.builtIn();
  DietProfile _profile = DietProfile.empty;

  /// EatPoint: an efficient shopping basket.
  bool _efficient = false;

  /// Household members who let others plan for them, and the ones this
  /// menu is also for.
  List<MemberSnapshot> _members = const [];
  final Set<String> _with = {};

  /// Every other member, the ones who can't be planned for yet included,
  /// so the section shows why.
  List<MemberSnapshot> _everyone = const [];

  /// Whether the menu is also for this user; off plans only for others.
  bool _forMe = true;

  /// EatPoint: foods the user always has in a meal, by meal id.
  Map<String, List<PlannedItem>> _fixed = const {};
  final FixedFoodsStore? _fixedStore = locator.isRegistered<FixedFoodsStore>()
      ? locator<FixedFoodsStore>()
      : null;

  Future<void> _addFixed(MealSlot slot) async {
    final item = await Navigator.of(context).push<PlannedItem>(
      MaterialPageRoute(
        builder: (_) => DishPickerScreen(day: _start, mealType: slot.baseType),
      ),
    );
    if (item == null || !mounted) return;
    setState(() {
      _fixed = {
        ..._fixed,
        slot.id: [...?_fixed[slot.id], item],
      };
    });
    await _fixedStore?.save(_fixed);
  }

  Future<void> _removeFixed(MealSlot slot, PlannedItem item) async {
    setState(() {
      _fixed = {
        ..._fixed,
        slot.id: [
          for (final i in _fixed[slot.id] ?? const <PlannedItem>[])
            if (i.id != item.id) i,
        ],
      };
    });
    await _fixedStore?.save(_fixed);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (locator.isRegistered<PointsSettingsDataSource>()) {
      final settings = await locator<PointsSettingsDataSource>().getSettings();
      _slots = settings.effectiveMealSlots;
    }
    _readProfile();
    _fixed = _fixedStore?.get() ?? const {};
    if (locator.isRegistered<HouseholdStore>()) {
      final store = locator<HouseholdStore>();
      if (store.getHousehold() != null) {
        _everyone = store.otherMembers();
        _members = [
          for (final m in _everyone)
            if (m.allowsEdits && m.profile != null) m,
        ];
      }
    }
    if (locator.isRegistered<AiCredentialStorage>()) {
      try {
        _aiAvailable =
            await locator<AiCredentialStorage>().readSelection() != null;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  void _readProfile() {
    _profile = locator.isRegistered<DietProfileStore>()
        ? locator<DietProfileStore>().get()
        : DietProfile.empty;
  }

  List<DateTime> get _dates => [
    for (var i = 0; i < _days; i++)
      DayPlan.dateOnly(DateTime(_start.year, _start.month, _start.day + i)),
  ];

  Future<void> _editProfile() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DietProfileScreen()));
    if (!mounted) return;
    setState(_readProfile);
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _start = DayPlan.dateOnly(picked));
  }

  Future<bool> _confirmAi() async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.generatorAiConfirmTitle),
        content: Text(s.generatorAiConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.generatorGenerate),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _generate() async {
    final s = S.of(context);
    final knowledge = FoodKnowledge.instance;
    if (knowledge == null || _busy) return;
    final lang = Localizations.localeOf(context).languageCode;
    final names = {
      for (final slot in _slots) slot: mealSlotLabel(context, slot),
    };
    if (_engine == _Engine.ai && !await _confirmAi()) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final checker = _profile.isEmpty ? null : DietChecker(_profile);
    final pool = await MenuGeneratorPool.build(knowledge, lang);
    final companions = <MemberSnapshot, MenuCompanion>{
      for (final m in _members)
        if (_with.contains(m.memberId)) m: _companionFor(m),
    };
    // Only for others: the first one's diet leads, instead of this user's.
    final lead = _forMe || companions.isEmpty ? null : companions.values.first;
    ImportedMenu menu;
    MenuFoodMatcher? matcher;
    GeneratedMenu? generated;
    try {
      if (_engine == _Engine.ai && companions.isEmpty) {
        final budget = locator.isRegistered<GetPointsBudgetUsecase>()
            ? await locator<GetPointsBudgetUsecase>().getBudget()
            : null;
        final brief = MenuGeneratorBrief.build(
          days: _dates,
          slots: _slots,
          nameOf: (slot) => names[slot]!,
          budgets: budget?.perSlot ?? const {},
          profile: _profile,
          languageCode: lang,
          ownDishes: _preferOwn ? MenuGeneratorPool.ownNames(pool) : const [],
          fixed: {
            for (final e in _fixed.entries)
              e.key: [
                for (final i in e.value)
                  '${i.name} (${i.amount.round()} ${i.unit})',
              ],
          },
        );
        menu = await RemoteMenuExtractor(
          http.Client(),
          locator<AiCredentialStorage>(),
        ).generate(brief, names.values.toList());
      } else {
        generated = MenuGenerator.generate(
          slots: _slots,
          nameOf: (slot) => names[slot]!,
          pool: pool,
          options: MenuGeneratorOptions(
            days: _dates,
            diet: lead?.diet ?? _profile.diet,
            preferOwn: _preferOwn,
            seed: _seed++,
            checker: lead == null ? checker : lead.checker,
            languageCode: lang,
            efficient: _efficient,
            companions: companions.values.toList(),
            leftoversLabel: s.generatorLeftovers,
            fixed: {
              for (final e in _fixed.entries)
                e.key: [
                  for (final i in e.value)
                    FixedFood(
                      GenFood.of(i.meal, knowledge: knowledge, own: true),
                      i.amount,
                    ),
                ],
            },
          ),
        );
        menu = generated.menu;
        matcher = GeneratedFoodMatcher(generated.foods, languageCode: lang);
      }
    } on RemoteExtractionException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = s.generatorAiFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (menu.isEmpty) {
      setState(() => _error = s.generatorNothing);
      return;
    }
    // Only for others: nothing goes into this user's menu.
    if (!_forMe && generated != null) {
      await _sendToMembers(generated, pool, companions, names, lang);
      if (mounted) Navigator.of(context).pop(_dates.length);
      return;
    }
    final saved = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => MenuImportReviewScreen(
          menu: menu,
          slots: _slots,
          initialWeek: _start,
          matcher: matcher,
        ),
      ),
    );
    if (saved == null || !mounted) return;
    if (generated != null && companions.isNotEmpty) {
      await _sendToMembers(generated, pool, companions, names, lang);
    }
    if (mounted) Navigator.of(context).pop(saved);
  }

  MenuCompanion _companionFor(MemberSnapshot member) {
    final diet = member.profile?.diet;
    return MenuCompanion(
      diet: diet?.diet ?? DietStyle.omnivore,
      checker: diet == null || diet.isEmpty ? null : DietChecker(diet),
    );
  }

  /// Gives each member chosen their share of the menu: the same dishes in
  /// their meals, fitted to their points, with what they can't eat swapped.
  /// It reaches their phone on the next sync.
  Future<void> _sendToMembers(
    GeneratedMenu generated,
    List<GenFood> pool,
    Map<MemberSnapshot, MenuCompanion> companions,
    Map<MealSlot, String> names,
    String lang,
  ) async {
    final store = locator<HouseholdStore>();
    final me = store.getHousehold()?.memberName ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    for (final entry in companions.entries) {
      final member = entry.key;
      final meals = MemberMenuAdapter.adapt(
        menu: generated.menu,
        foods: generated.foods,
        mySlots: _slots,
        myNameOf: (slot) => names[slot]!,
        theirSlots: memberSlots(member, null),
        theirBudgets: member.profile?.budgets ?? const {},
        pool: pool,
        them: entry.value,
        languageCode: lang,
        start: _start,
      );
      for (final meal in meals) {
        await store.editMemberMenu(
          MenuEdit(
            id: IdGenerator.getUniqueID(),
            memberId: member.memberId,
            date: meal.date,
            slotId: meal.slotId,
            items: meal.items,
            by: me,
            at: DateTime.now(),
          ),
        );
      }
      messenger.showSnackBar(
        SnackBar(content: Text(s.generatorSentTo(member.name))),
      );
    }
    HouseholdAutoSync.instance.syncSoon(Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final startLabel = MaterialLocalizations.of(
      context,
    ).formatMediumDate(_start);
    Widget section(String text) => Padding(
      padding: const EdgeInsets.only(
        top: Dimens.spacing24,
        bottom: Dimens.spacing8,
      ),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget help(String text) => Padding(
      padding: const EdgeInsets.only(top: Dimens.spacing8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.generatorTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing8,
          Dimens.spacing16,
          Dimens.spacing32,
        ),
        children: [
          Text(s.generatorIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Dimens.spacing16),
          _DietSummaryCard(profile: _profile, onEdit: _editProfile),
          section(s.generatorDaysTitle),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              identifier: 'generator-start',
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text(s.generatorFrom(startLabel)),
                onPressed: _pickStart,
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          Semantics(
            identifier: 'generator-days',
            child: Wrap(
              spacing: Dimens.spacing8,
              children: [
                for (final n in _dayCounts)
                  ChoiceChip(
                    label: Text(
                      n == 1 ? s.generatorOneDay : s.generatorDays('$n'),
                    ),
                    selected: _days == n,
                    onSelected: (_) => setState(() => _days = n),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          Semantics(
            identifier: 'generator-prefer-own',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.generatorPreferOwn),
              subtitle: Text(s.generatorPreferOwnHelp),
              value: _preferOwn,
              onChanged: (v) => setState(() => _preferOwn = v),
            ),
          ),
          Semantics(
            identifier: 'generator-efficient',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.generatorEfficient),
              subtitle: Text(s.generatorEfficientHelp),
              value: _efficient,
              onChanged: (v) => setState(() {
                _efficient = v;
                if (v) _engine = _Engine.phone;
              }),
            ),
          ),
          // EatPoint: foods the user always has in a meal.
          section(s.generatorFixedTitle),
          for (final slot in _slots)
            Padding(
              padding: const EdgeInsets.only(bottom: Dimens.spacing8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Padding(
                      padding: const EdgeInsets.only(top: Dimens.spacing8),
                      child: Text(
                        mealSlotLabel(context, slot),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: Dimens.spacing8,
                      runSpacing: Dimens.spacing4,
                      children: [
                        for (final item
                            in _fixed[slot.id] ?? const <PlannedItem>[])
                          InputChip(
                            label: Text(
                              '${item.name} · '
                              '${PointsFormat.of(context).grams(item.amount)} '
                              '${item.unit}',
                            ),
                            onDeleted: () => _removeFixed(slot, item),
                          ),
                        Semantics(
                          identifier: 'generator-fixed-add-${slot.id}',
                          child: ActionChip(
                            avatar: const Icon(Icons.add_rounded, size: 18),
                            label: Text(s.generatorFixedAdd),
                            onPressed: () => _addFixed(slot),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          help(s.generatorFixedHelp),
          // EatPoint: everyone in the household, chosen by hand; who can't
          // be planned for yet is shown with the reason.
          if (_everyone.isNotEmpty) ...[
            section(s.generatorForWhom),
            Wrap(
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing8,
              children: [
                Semantics(
                  identifier: 'generator-for-me',
                  child: FilterChip(
                    label: Text(s.generatorForMe),
                    selected: _forMe,
                    // Someone has to be left to plan for.
                    onSelected: _forMe && _with.isEmpty
                        ? null
                        : (v) => setState(() => _forMe = v),
                  ),
                ),
                for (final m in _everyone)
                  Semantics(
                    identifier: 'generator-with-${m.memberId}',
                    child: FilterChip(
                      avatar: MemberAvatar(
                        name: m.name,
                        colourKey: m.memberId,
                        radius: 10,
                      ),
                      label: Text(m.name),
                      selected: _with.contains(m.memberId),
                      onSelected: !_members.contains(m)
                          ? null
                          : (v) => setState(() {
                              v
                                  ? _with.add(m.memberId)
                                  : _with.remove(m.memberId);
                              if (v) _engine = _Engine.phone;
                              // Leaving nobody: back to this user.
                              if (_with.isEmpty) _forMe = true;
                            }),
                    ),
                  ),
              ],
            ),
            help(s.generatorForWhomHelp),
            for (final m in _everyone)
              if (m.profile == null)
                help(s.generatorMemberNoProfile(m.name))
              else if (!m.allowsEdits)
                help(s.generatorMemberNoEdits(m.name)),
          ],
          section(s.generatorEngineTitle),
          Semantics(
            identifier: 'generator-engine',
            child: SegmentedButton<_Engine>(
              segments: [
                ButtonSegment(
                  value: _Engine.phone,
                  icon: const Icon(Icons.phone_android_rounded),
                  label: Text(s.generatorEnginePhone),
                ),
                ButtonSegment(
                  value: _Engine.ai,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(s.generatorEngineAi),
                  enabled: _aiAvailable && _with.isEmpty && !_efficient,
                ),
              ],
              selected: {_engine},
              onSelectionChanged: (v) => setState(() => _engine = v.first),
            ),
          ),
          help(
            _engine == _Engine.phone
                ? s.generatorEnginePhoneHelp
                : s.generatorEngineAiHelp,
          ),
          if (!_aiAvailable) help(s.generatorAiNotSet),
          if (_error != null) ...[
            const SizedBox(height: Dimens.spacing16),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: Dimens.spacing24),
          Semantics(
            identifier: 'generator-generate',
            child: FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_rounded),
              label: Text(_busy ? s.generatorGenerating : s.generatorGenerate),
              onPressed: _busy ? null : _generate,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the generator will follow, in one card, with a way to change it.
class _DietSummaryCard extends StatelessWidget {
  final DietProfile profile;
  final VoidCallback onEdit;

  const _DietSummaryCard({required this.profile, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    String list(Iterable<String> items) => items.join(', ');
    final lines = profile.isEmpty
        ? [s.generatorDietNone]
        : [
            [
              profile.diet.label(s),
              if (profile.religion != ReligiousDiet.none)
                profile.religion.label(s),
            ].join(' · '),
            if (profile.allergies.isNotEmpty)
              s.generatorAllergies(
                list(profile.allergies.map((a) => a.label(s).toLowerCase())),
              ),
            if (profile.intolerances.isNotEmpty)
              s.generatorIntolerances(
                list(profile.intolerances.map((i) => i.label(s).toLowerCase())),
              ),
            if (profile.likes.isNotEmpty) s.generatorLikes(list(profile.likes)),
            if (profile.dislikes.isNotEmpty)
              s.generatorDislikes(list(profile.dislikes)),
          ];
    return Semantics(
      identifier: 'generator-diet',
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing12,
            Dimens.spacing8,
            Dimens.spacing12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.no_food_outlined),
              const SizedBox(width: Dimens.spacing12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.generatorDietCard,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: Dimens.spacing4),
                    for (final line in lines)
                      Text(line, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              TextButton(onPressed: onEdit, child: Text(s.generatorDietEdit)),
            ],
          ),
        ),
      ),
    );
  }
}
