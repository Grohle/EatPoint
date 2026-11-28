import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/add_item_bottom_sheet.dart';
import 'package:opennutritracker/core/presentation/widgets/demo_mode_banner.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/health_rationale_service.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/presentation/widgets/home_appbar.dart';
import 'package:opennutritracker/features/home/home_page.dart';
import 'package:opennutritracker/core/presentation/widgets/main_appbar.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/domain/shopping_list_builder.dart';
import 'package:opennutritracker/features/planner/presentation/planner_screen.dart';
import 'package:opennutritracker/features/planner/presentation/shopping_list_screen.dart';
import 'package:opennutritracker/features/profile/profile_page.dart';
import 'package:opennutritracker/features/trends/presentation/trends_page.dart';
import 'package:opennutritracker/features/updates/presentation/update_prompt.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/features/backup/presentation/backup_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedPageIndex = 0;
  bool _isDemoData = false;

  /// Guards against two lifecycle events asking the platform at once. The
  /// platform side clears the flag on read, so a race would not open the
  /// screen twice — but it would spend two channel round trips finding out.
  bool _checkingHealthRationale = false;

  late List<Widget> _bodyPages;
  late List<PreferredSizeWidget> _appbarPages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConfigDrivenUi();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // The activity is singleTop, so Health Connect reaching a process that is
    // already running never rebuilds this screen — a resume is the only signal
    // that an intent arrived.
    if (state == AppLifecycleState.resumed) {
      _maybeOpenHealthRationale();
    }
  }

  // Checked once per screen instance rather than kept live — leaving demo mode
  // always replaces this whole screen with the onboarding route (see
  // DemoModeBanner), so there is no in-place transition to react to.
  //
  // The policy-change notice #887 specified is deliberately **not** shown for
  // revision 1. #887's reasoning stands on the record and was not refuted —
  // the corrections name recipients that were always receiving data, so users
  // were under-informed for the whole time rather than recently — but the call
  // was made not to spend a first-launch dialog on it. The mechanism itself is
  // kept, not deleted: `URLConst.policyRevision`, the seeding in
  // `OnboardingBloc.saveOnboardingData` and `PolicyChangeDialog` are all still
  // live and tested, so a future revision that does warrant telling people can
  // restore this by calling the dialog again. What is gone is one call, not
  // the ability to notify.
  Future<void> _loadConfigDrivenUi() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!mounted) return;
    setState(() => _isDemoData = config.isDemoData);
    await _maybeOpenHealthRationale();
    // EatPoint: bring the food database up to date and offer a newer
    // release, if any (off in demo mode).
    if (mounted && !config.isDemoData) {
      unawaited(maybeAutoBackup());
      unawaited(maybeUpdateFoodDb(context));
      await maybeOfferUpdate(context);
    }
  }

  /// Opens the health-sync screen when Health Connect asked the app to explain
  /// what it wants health data for (#927).
  ///
  /// Health Connect starts the app rather than rendering anything itself, so
  /// without this the user is dropped on the diary having asked a question
  /// nothing answered. The screen names the data, says what it is used for,
  /// and links the privacy policy.
  Future<void> _maybeOpenHealthRationale() async {
    if (_checkingHealthRationale) return;
    _checkingHealthRationale = true;
    final bool requested;
    try {
      requested = await HealthRationaleService.consumePendingRequest();
    } finally {
      _checkingHealthRationale = false;
    }
    if (!requested || !mounted) return;
    await Navigator.of(context).pushNamed(NavigationOptions.healthSyncRoute);
  }

  @override
  void didChangeDependencies() {
    // EatPoint: "My day" joins the diary and the menu; it brings its own
    // app bar (whose menu, calendar, the full diary).
    _bodyPages = [
      const HomePage(),
      const PlannerScreen(embedded: true),
      const TrendsPage(),
      const ProfilePage(),
    ];
    _appbarPages = [
      const HomeAppbar(),
      MainAppbar(title: S.of(context).myDayLabel, iconData: Icons.today),
      MainAppbar(title: S.of(context).trendsLabel, iconData: Icons.insights),
      MainAppbar(title: S.of(context).youLabel, iconData: Icons.account_circle),
    ];
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return Scaffold(
      appBar: _selectedPageIndex == 1 ? null : _appbarPages[_selectedPageIndex],
      body: Column(
        children: [
          if (_isDemoData) const DemoModeBanner(),
          Expanded(
            child: IndexedStack(
              index: _selectedPageIndex,
              children: _bodyPages,
            ),
          ),
        ],
      ),
      floatingActionButton: Semantics(
        identifier: 'fab-add-item',
        child: FloatingActionButton(
          onPressed: () => _onFabPressed(context),
          tooltip: S.of(context).addLabel,
          child: const Icon(Icons.add, size: 30),
        ),
      ),
      // EatPoint: Add sits at the right, above the bar; the centre is the
      // shopping list.
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: BottomAppBar(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 78,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            _NavItem(
              id: 'nav-home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: S.of(context).homeLabel,
              index: 0,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
            _NavItem(
              id: 'nav-diary',
              icon: Icons.today_outlined,
              selectedIcon: Icons.today_rounded,
              label: S.of(context).myDayLabel,
              index: 1,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
            const _ShoppingNavButton(),
            _NavItem(
              id: 'nav-trends',
              icon: Icons.insights_outlined,
              selectedIcon: Icons.insights_rounded,
              label: S.of(context).trendsLabel,
              index: 2,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
            _NavItem(
              id: 'nav-you',
              icon: Icons.account_circle_outlined,
              selectedIcon: Icons.account_circle_rounded,
              label: S.of(context).youLabel,
              index: 3,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
          ],
        ),
      ),
    );
  }

  void _setPage(int selectedIndex) {
    setState(() {
      _selectedPageIndex = selectedIndex;
    });
  }

  Future<void> _onFabPressed(BuildContext context) async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // A tall sheet (large font) stops below the status bar.
      useSafeArea: true,
      builder: (BuildContext context) {
        return AddItemBottomSheet(
          day: DateTime.now(),
          showActivityTracking: config.showActivityTracking,
          usesImperialUnits: config.usesImperialFoodUnits,
          suggestedType: MealTypeSuggester.suggestFromTime(
            DateTime.now(),
            mealSharesPct: config.mealKcalSharesPct,
          ),
        );
      },
    );
  }
}

/// EatPoint: the shopping list, in the middle of the bar, with how many
/// things of this week are still to buy.
class _ShoppingNavButton extends StatefulWidget {
  const _ShoppingNavButton();

  @override
  State<_ShoppingNavButton> createState() => _ShoppingNavButtonState();
}

class _ShoppingNavButtonState extends State<_ShoppingNavButton> {
  final PlannerDataSource? _source = locator.isRegistered<PlannerDataSource>()
      ? locator<PlannerDataSource>()
      : null;

  @override
  void initState() {
    super.initState();
    _source?.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    _source?.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  int _pending() {
    final source = _source;
    if (source == null) return 0;
    final today = DateTime.now();
    final state = source.getShopping(today);
    final built = ShoppingListBuilder.build([
      for (final d in source.getWeek(today)) (owner: 'me', plan: d),
    ]);
    final keys = {for (final i in built) i.key};
    return [
      ...built,
      ...state.manualItems.where((m) => !keys.contains(m.key)),
    ].where((i) => !state.checked.contains(i.key)).length;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = _pending();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Semantics(
        identifier: 'nav-shopping',
        button: true,
        label: S.of(context).shoppingTitle,
        child: Badge(
          isLabelVisible: pending > 0,
          label: Text('$pending'),
          offset: const Offset(-4, 4),
          child: Material(
            color: scheme.primaryContainer,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ShoppingListScreen(
                    weekOf: DayPlan.weekStart(DateTime.now()),
                  ),
                ),
              ),
              child: SizedBox.square(
                dimension: 56,
                child: Icon(
                  Icons.shopping_cart_outlined,
                  color: scheme.onPrimaryContainer,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String id;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int index;
  final int selectedIndex;
  final AppPalette palette;
  final void Function(int) onTap;

  const _NavItem({
    required this.id,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = index == selectedIndex;
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : palette.textMuted;
    return Expanded(
      child: Semantics(
        identifier: id,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? selectedIcon : icon, color: color, size: 26),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
