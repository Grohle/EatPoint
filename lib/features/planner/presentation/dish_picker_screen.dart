import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/food_db/domain/food_database.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/food_search_tab_view.dart';
import 'package:opennutritracker/features/planner/domain/shopping_list_builder.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/features/diet_profile/presentation/diet_warning.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// A dish the user has eaten or saved before, with the amount they usually
/// have.
class PastDish {
  final MealEntity meal;
  final double usualAmount;
  final PastDishSource source;
  final DateTime? lastUsed;

  const PastDish(this.meal, this.usualAmount, this.source, {this.lastUsed});

  String get unit => meal.isLiquid ? 'ml' : 'g';
}

/// How well [name] matches [query], 0 for no match. Accents and case do
/// not matter, the words may come in any order, and each may be the
/// start of a word ("pech poll" finds "Pechuga de pollo").
double dishMatchScore(String name, String query) {
  final n = FoodKnowledge.fold(name);
  final q = FoodKnowledge.fold(query).trim();
  if (q.isEmpty) return 1;
  if (n == q) return 4;
  if (n.startsWith(q)) return 3;
  final words = n.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty);
  var score = 2.0;
  for (final part in q.split(RegExp(r'\s+'))) {
    if (part.isEmpty) continue;
    if (words.any((w) => w.startsWith(part))) continue;
    if (n.contains(part)) {
      score -= 0.5;
      continue;
    }
    return 0;
  }
  return score;
}

/// Where a past dish comes from.
enum PastDishSource { recent, recipe, favourite, basic, database }

enum _Tab { fits, recent, recipes, favourites }

/// Picks a dish for a planned meal from what the user has logged or saved
/// before, sorted by how well it fits the points left in that meal.
/// Returns the [PlannedItem] to add, or null.
class DishPickerScreen extends StatefulWidget {
  final DateTime day;
  final IntakeTypeEntity mealType;

  /// Points still free in the meal; null when there is no budget.
  final MacroPoints? remaining;

  const DishPickerScreen({
    super.key,
    required this.day,
    required this.mealType,
    this.remaining,
  });

  @override
  State<DishPickerScreen> createState() => _DishPickerScreenState();
}

class _DishPickerScreenState extends State<DishPickerScreen> {
  final _search = TextEditingController();
  _Tab _tab = _Tab.fits;
  bool _scaleToFit = true;
  List<PastDish>? _dishes;

  /// EatPoint's basic foods, found only by searching.
  List<PastDish> _basics = const [];

  bool _loadStarted = false;

  // Loads once the locale is known: the basic foods are named in it.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dishes = <String, PastDish>{};
    String key(MealEntity m) => ShoppingListBuilder.normalise(m.name ?? '');

    try {
      final recent = await locator<GetIntakeUsecase>().getRecentIntake();
      for (final intake in recent) {
        final k = key(intake.meal);
        if (k.isEmpty) continue;
        final existing = dishes[k];
        if (existing == null ||
            (existing.lastUsed != null &&
                intake.dateTime.isAfter(existing.lastUsed!))) {
          dishes[k] = PastDish(
            intake.meal,
            intake.amount,
            PastDishSource.recent,
            lastUsed: intake.dateTime,
          );
        }
      }
    } catch (_) {}
    try {
      for (final dbo in locator<RecipeDataSource>().getAllRecipes()) {
        final recipe = RecipeEntity.fromDBO(dbo);
        final meal = recipe.toMealEntity();
        final servings = recipe.servingsCount;
        final serving = servings != null && servings > 0
            ? recipe.totalWeightG / servings
            : recipe.totalWeightG;
        dishes.putIfAbsent(
          'recipe:${recipe.id}',
          () => PastDish(
            meal,
            serving > 0 ? serving : 100,
            PastDishSource.recipe,
          ),
        );
      }
    } catch (_) {}
    try {
      for (final fav in locator<HiveDBProvider>().favouriteMealBox.values) {
        final meal = MealEntity.fromMealDBO(fav.meal);
        final k = key(meal);
        if (k.isEmpty) continue;
        dishes.putIfAbsent(
          k,
          () => PastDish(
            meal,
            meal.scalableServingQuantity ?? 100,
            PastDishSource.favourite,
          ),
        );
      }
    } catch (_) {}
    final basics = <PastDish>[];
    final knowledge = FoodKnowledge.instance;
    if (knowledge != null && mounted) {
      final lang = Localizations.localeOf(context).languageCode;
      for (final food in knowledge.foods) {
        final portion = knowledge.conceptById(food.conceptId)?.mainPortion;
        basics.add(
          PastDish(
            food.toMealEntity(lang),
            portion?.grams ?? 100,
            PastDishSource.basic,
          ),
        );
      }
    }
    if (!mounted) return;
    bool hasPoints(PastDish d) =>
        d.meal.pointsPer100 != null && d.meal.pointsPer100! > 0;
    setState(() {
      _dishes = dishes.values.where(hasPoints).toList();
      _basics = basics.where(hasPoints).toList();
    });
  }

  List<PastDish> _matching(List<PastDish> from, String query, int limit) {
    final scored =
        [
          for (final d in from)
            if (dishMatchScore(d.meal.name ?? '', query) case final sc
                when sc > 0)
              (d, sc),
        ]..sort((a, b) {
          final byScore = b.$2.compareTo(a.$2);
          return byScore != 0
              ? byScore
              : _fitScore(a.$1).compareTo(_fitScore(b.$1));
        });
    return [for (final (d, _) in scored.take(limit)) d];
  }

  /// Opens the recipe builder; a recipe saved there is offered straight
  /// away.
  Future<void> _createRecipe() async {
    final before = {
      for (final d in _dishes ?? const <PastDish>[])
        if (d.source == PastDishSource.recipe) d.meal.code,
    };
    await Navigator.of(context).pushNamed(NavigationOptions.recipeBuilderRoute);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    final created = (_dishes ?? const <PastDish>[])
        .where(
          (d) =>
              d.source == PastDishSource.recipe &&
              !before.contains(d.meal.code),
        )
        .firstOrNull;
    if (created != null) await _choose(created);
  }

  /// Searches the food databases, starting with what is typed.
  Future<void> _searchDatabases() async {
    final s = S.of(context);
    final meal = await Navigator.of(context).push<MealEntity>(
      MaterialPageRoute(
        builder: (searchContext) => Scaffold(
          appBar: AppBar(title: Text(s.plannerSearchFoodTitle)),
          body: FoodSearchTabView(
            initialQuery: _search.text,
            onMealSelected: (meal) => Navigator.of(searchContext).pop(meal),
          ),
        ),
      ),
    );
    if (meal == null || !mounted) return;
    await _choose(
      PastDish(
        meal,
        meal.scalableServingQuantity ?? 100,
        PastDishSource.database,
      ),
    );
  }

  /// The amount to plan: the usual amount, or scaled so the dish's points
  /// match what is left in the meal.
  double _amountFor(PastDish dish) {
    final remaining = widget.remaining;
    if (!_scaleToFit || remaining == null || remaining.total <= 0.1) {
      return dish.usualAmount;
    }
    // A basic food is one ingredient of the meal, not all of it.
    if (dish.source == PastDishSource.basic) return dish.usualAmount;
    final result = PointsCalc.pointsToGrams(
      remaining.total,
      dish.meal.pointsPer100!,
    );
    return result.roundedGrams > 0 ? result.roundedGrams : dish.usualAmount;
  }

  /// 0 is a perfect fit. Compares the dish's split with what is left and,
  /// when not scaling, its size with the points left.
  double _fitScore(PastDish dish) {
    final remaining = widget.remaining;
    if (remaining == null || remaining.total <= 0.1) return 0;
    final points = dish.meal.nutriments.macroPointsFor(_amountFor(dish));
    double share(double part, double total) => total <= 0 ? 0 : part / total;
    final shapeGap =
        (share(points.carbs, points.total) -
                share(remaining.carbs, remaining.total))
            .abs() +
        (share(points.protein, points.total) -
                share(remaining.protein, remaining.total))
            .abs() +
        (share(points.fat, points.total) -
                share(remaining.fat, remaining.total))
            .abs();
    final sizeGap = (points.total - remaining.total).abs() / remaining.total;
    return shapeGap + sizeGap;
  }

  List<PastDish> _visible() {
    final query = ShoppingListBuilder.normalise(_search.text);
    var list = (_dishes ?? const <PastDish>[]).where((d) {
      if (query.isNotEmpty &&
          !ShoppingListBuilder.normalise(d.meal.name ?? '').contains(query)) {
        return false;
      }
      return switch (_tab) {
        _Tab.fits => true,
        _Tab.recent => d.source == PastDishSource.recent,
        _Tab.recipes => d.source == PastDishSource.recipe,
        _Tab.favourites => d.source == PastDishSource.favourite,
      };
    }).toList();
    if (_tab == _Tab.recent) {
      list.sort(
        (a, b) =>
            (b.lastUsed ?? DateTime(0)).compareTo(a.lastUsed ?? DateTime(0)),
      );
    } else {
      list.sort((a, b) => _fitScore(a).compareTo(_fitScore(b)));
    }
    return list.take(60).toList();
  }

  Future<void> _choose(PastDish dish) async {
    if (!await confirmDietConflicts(
      context,
      dish.meal.name ?? '',
      code: dish.meal.code,
    )) {
      return;
    }
    if (!mounted) return;
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _AmountDialog(dish: dish, initial: _amountFor(dish)),
    );
    if (amount == null || amount <= 0 || !mounted) return;
    Navigator.of(context).pop(
      PlannedItem(
        id: IdGenerator.getUniqueID(),
        meal: dish.meal,
        amount: amount,
        unit: dish.unit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final format = PointsFormat.of(context);
    final remaining = widget.remaining;
    final dishes = _dishes;
    final dayName = MaterialLocalizations.of(
      context,
    ).formatFullDate(widget.day).split(',').first;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.plannerPickTitle(
                mealTypeLabel(context, widget.mealType),
                dayName,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (remaining != null)
              Text(
                s.plannerPickLeft(format.points(math.max(0, remaining.total))),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing16,
              Dimens.spacing8,
              Dimens.spacing16,
              0,
            ),
            child: Semantics(
              identifier: 'planner-pick-search',
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).deleteButtonTooltip,
                          onPressed: () => setState(_search.clear),
                        ),
                  hintText: s.plannerPickSearch,
                  border: const OutlineInputBorder(
                    borderRadius: Dimens.borderRadiusL,
                  ),
                ),
              ),
            ),
          ),
          if (_search.text.trim().isEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(Dimens.spacing12),
              child: Row(
                children: [
                  for (final (tab, label) in [
                    (_Tab.fits, s.plannerTabFits),
                    (_Tab.recent, s.plannerTabRecent),
                    (_Tab.recipes, s.plannerTabRecipes),
                    (_Tab.favourites, s.plannerTabFavourites),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: Dimens.spacing8),
                      child: Semantics(
                        identifier: 'planner-pick-tab-${tab.name}',
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _tab == tab,
                          onSelected: (_) => setState(() => _tab = tab),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (_search.text.trim().isNotEmpty)
            const SizedBox(height: Dimens.spacing8),
          if (remaining != null)
            Semantics(
              identifier: 'planner-pick-scale',
              child: SwitchListTile(
                dense: true,
                title: Text(s.plannerScaleToFit),
                value: _scaleToFit,
                onChanged: (v) => setState(() => _scaleToFit = v),
              ),
            ),
          Expanded(
            child: dishes == null
                ? const Center(child: CircularProgressIndicator())
                : _search.text.trim().isNotEmpty
                ? _searchResults(context)
                : _list(context),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final s = S.of(context);
    final visible = _visible();
    if ((_dishes ?? const []).isEmpty) return _emptyState(context);
    if (_tab == _Tab.recipes && visible.isEmpty) {
      return _emptyState(context, recipesOnly: true);
    }
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Dimens.spacing24),
        child: Text(
          s.plannerNoDishes,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        0,
        Dimens.spacing16,
        Dimens.spacing24,
      ),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: Dimens.spacing8),
      itemBuilder: (context, i) => _dishCard(context, visible[i]),
    );
  }

  Widget _dishCard(BuildContext context, PastDish dish) {
    final s = S.of(context);
    final format = PointsFormat.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final amount = _amountFor(dish);
    final portion = PortionFormatter.forFood(
      dish.meal.name ?? '',
      amount,
    )?.label(Localizations.localeOf(context).languageCode);
    final points = dish.meal.nutriments.macroPointsFor(amount);
    final fits = widget.remaining != null && _fitScore(dish) < 0.35;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: Dimens.borderRadiusL,
        side: BorderSide(
          color: fits ? Theme.of(context).colorScheme.primary : palette.border,
          width: fits ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: Dimens.borderRadiusL,
        onTap: () => _choose(dish),
        child: Padding(
          padding: const EdgeInsets.all(Dimens.spacing12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: Dimens.spacing8),
                    child: Icon(
                      _sourceIcon(dish.source),
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      dish.meal.name ?? '',
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: Dimens.spacing4),
                    child: DietBadge(dish.meal.name ?? '', code: dish.meal.code),
                  ),
                  if (fits)
                    Chip(
                      label: Text(s.plannerFits),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: Dimens.spacing4),
              Wrap(
                spacing: Dimens.spacing8,
                runSpacing: Dimens.spacing4,
                children: [
                  Text(
                    '${format.grams(amount)} ${dish.unit}'
                    '${portion == null ? '' : ' (≈ $portion)'} · '
                    '${format.points(points.total)} ${s.pointsShort}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (points.carbs >= 0.05)
                    _Dot(palette.carbs, format.points(points.carbs)),
                  if (points.protein >= 0.05)
                    _Dot(palette.protein, format.points(points.protein)),
                  if (points.fat >= 0.05)
                    _Dot(palette.fat, format.points(points.fat)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _sourceIcon(PastDishSource source) => switch (source) {
    PastDishSource.recent => Icons.history_rounded,
    PastDishSource.recipe => Icons.menu_book_rounded,
    PastDishSource.favourite => Icons.star_rounded,
    PastDishSource.basic => Icons.eco_rounded,
    PastDishSource.database => Icons.travel_explore_rounded,
  };

  /// What to show when typing: the user's own dishes first, then EatPoint's
  /// basic foods, then a way into the food databases.
  Widget _searchResults(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final query = _search.text.trim();
    final own = _matching(_dishes ?? const [], query, 30);
    final basics = _matching(_basics, query, 12);
    final lang = Localizations.localeOf(context).languageCode;
    final fromDb = [
      for (final f in FoodDatabase.instance?.search(
            query,
            languageCode: lang,
            limit: 15,
          ) ??
          const <FoodDbEntry>[])
        PastDish(
          f.toMealEntity(lang),
          f.servingGrams ?? 100,
          PastDishSource.database,
        ),
    ];
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        0,
        Dimens.spacing8,
        0,
        Dimens.spacing8,
      ),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        0,
        Dimens.spacing16,
        Dimens.spacing24,
      ),
      children: [
        if (own.isNotEmpty) ...[
          header(s.plannerSearchYourDishes),
          for (final dish in own) ...[
            _dishCard(context, dish),
            const SizedBox(height: Dimens.spacing8),
          ],
        ],
        if (basics.isNotEmpty) ...[
          header(s.plannerSearchBasicFoods),
          for (final dish in basics) ...[
            _dishCard(context, dish),
            const SizedBox(height: Dimens.spacing8),
          ],
        ],
        if (fromDb.isNotEmpty) ...[
          header(s.foodDbTitle),
          for (final dish in fromDb) ...[
            _dishCard(context, dish),
            const SizedBox(height: Dimens.spacing8),
          ],
        ],
        if (own.isEmpty && basics.isEmpty && fromDb.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: Text(
              s.plannerSearchNoMatches(query),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: Dimens.spacing8),
        Semantics(
          identifier: 'planner-pick-search-databases',
          child: OutlinedButton.icon(
            icon: const Icon(Icons.travel_explore_rounded),
            label: Text(s.plannerSearchDatabases(query)),
            onPressed: _searchDatabases,
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        Semantics(
          identifier: 'planner-pick-search-create-recipe',
          child: TextButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: Text(s.plannerCreateRecipe),
            onPressed: _createRecipe,
          ),
        ),
      ],
    );
  }

  /// No dishes yet (or no recipes on the Recipes tab): offers to create a
  /// recipe or find a food.
  Widget _emptyState(BuildContext context, {bool recipesOnly = false}) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Dimens.spacing24),
      children: [
        Icon(
          Icons.menu_book_rounded,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: Dimens.spacing12),
        Text(
          recipesOnly ? s.plannerNoRecipesTitle : s.plannerEmptyTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: Dimens.spacing8),
        Text(
          s.plannerEmptyBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Dimens.spacing24),
        Semantics(
          identifier: 'planner-pick-create-recipe',
          child: FilledButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: Text(s.plannerCreateRecipe),
            onPressed: _createRecipe,
          ),
        ),
        const SizedBox(height: Dimens.spacing8),
        Semantics(
          identifier: 'planner-pick-find-food',
          child: OutlinedButton.icon(
            icon: const Icon(Icons.search_rounded),
            label: Text(s.plannerFindFood),
            onPressed: _searchDatabases,
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final String text;

  const _Dot(this.color, this.text);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(text, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _AmountDialog extends StatefulWidget {
  final PastDish dish;
  final double initial;

  const _AmountDialog({required this.dish, required this.initial});

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.text.isEmpty) {
      _controller.text = PointsFormat.of(context).grams(widget.initial);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final format = PointsFormat.of(context);
    final amount = PointsFormat.parse(_controller.text) ?? 0;
    final points = widget.dish.meal.nutriments.macroPointsFor(amount);
    return AlertDialog(
      title: Text(s.plannerAmountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.dish.meal.name ?? ''),
          const SizedBox(height: Dimens.spacing12),
          Semantics(
            identifier: 'planner-amount-field',
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,5}([.,]\d{0,1})?$'),
                ),
              ],
              decoration: InputDecoration(
                suffixText: widget.dish.unit,
                border: const OutlineInputBorder(
                  borderRadius: Dimens.borderRadiusM,
                ),
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          Text(
            '${format.points(points.total)} ${s.pointsShort}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: amount > 0 ? () => Navigator.pop(context, amount) : null,
          child: Text(s.plannerAdd),
        ),
      ],
    );
  }
}
