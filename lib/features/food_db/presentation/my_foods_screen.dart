import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/food_db/domain/food_database.dart';
import 'package:opennutritracker/features/food_knowledge/data/portion_override_store.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';
import 'package:opennutritracker/features/food_knowledge/presentation/unit_weight_dialog.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// EatPoint's food editor: the user's own foods and the whole food
/// database in one place. New foods are created here; any food can be
/// edited and is then kept as the user's own; and each food's weight per
/// unit can be set.
class MyFoodsScreen extends StatefulWidget {
  final CustomMealDataSource? customMeals;

  const MyFoodsScreen({super.key, this.customMeals});

  @override
  State<MyFoodsScreen> createState() => _MyFoodsScreenState();
}

class _MyFoodsScreenState extends State<MyFoodsScreen> {
  late final CustomMealDataSource _custom =
      widget.customMeals ?? locator<CustomMealDataSource>();
  final _query = TextEditingController();
  StreamSubscription<void>? _watch;
  final PortionOverrideStore? _portions =
      locator.isRegistered<PortionOverrideStore>()
      ? locator<PortionOverrideStore>()
      : null;

  @override
  void initState() {
    super.initState();
    _watch = _custom.watch().listen((_) => _refresh());
    _portions?.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    _watch?.cancel();
    _portions?.revision.removeListener(_refresh);
    _query.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String get _lang => Localizations.localeOf(context).languageCode;

  List<MealEntity> _mine() {
    final q = FoodKnowledge.fold(_query.text).trim();
    final all = [
      for (final dbo in _custom.getAllCustomMeals())
        MealEntity.fromMealDBO(dbo),
    ];
    final hits = q.isEmpty
        ? all
        : all
              .where((m) => FoodKnowledge.fold(m.name ?? '').contains(q))
              .toList();
    hits.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    return hits;
  }

  /// Foods of the database (or, without it, EatPoint's basic foods) for
  /// the search, leaving out the ones already among the user's own.
  List<MealEntity> _database(Set<String> mine) {
    final q = _query.text.trim();
    if (q.length < 2) return const [];
    final db = FoodDatabase.instance;
    final results = <MealEntity>[
      if (db != null)
        for (final f in db.search(q, languageCode: _lang, limit: 40))
          f.toMealEntity(_lang)
      else if (FoodKnowledge.instance case final k?)
        for (final f in k.foods)
          if (FoodKnowledge.fold(
            f.toMealEntity(_lang).name ?? '',
          ).contains(FoodKnowledge.fold(q)))
            f.toMealEntity(_lang),
    ];
    return [
      for (final m in results)
        if (!mine.contains(FoodKnowledge.fold(m.name ?? ''))) m,
    ];
  }

  Future<void> _edit(MealEntity meal) async {
    await Navigator.of(context).pushNamed(
      NavigationOptions.editMealRoute,
      arguments: EditMealScreenArguments(
        DateTime.now(),
        meal,
        IntakeTypeEntity.breakfast,
        false,
        editOnly: true,
      ),
    );
    _refresh();
  }

  Future<void> _delete(MealEntity meal) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.customMealsDeleteConfirmTitle),
        content: Text(s.customMealsDeleteConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(MaterialLocalizations.of(context).deleteButtonTooltip),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _custom.deleteCustomMeal(meal.code ?? meal.name ?? '');
    _refresh();
  }

  Widget _tile(MealEntity meal, {required bool mine}) {
    final s = S.of(context);
    final format = PointsFormat.of(context);
    final name = meal.name ?? '';
    final portion = FoodPortions.of(name, code: meal.code);
    final kcal = meal.nutriments.energyKcal100;
    final unit = meal.isLiquid ? 'ml' : 'g';
    final details = [
      if (kcal != null) '${format.grams(kcal)} kcal/100 $unit',
      if (portion != null)
        s.myFoodsUnitWeight(
          portion.name(_lang, 1),
          '${format.grams(portion.grams)} g',
        ),
    ].join(' · ');
    return ListTile(
      key: ValueKey('${mine ? 'mine' : 'db'}-${meal.code ?? name}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        mine ? Icons.person_outline_rounded : Icons.storage_rounded,
        size: 20,
      ),
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty ? null : Text(details),
      onTap: () => _edit(meal),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          switch (action) {
            case 'edit':
              await _edit(meal);
            case 'unit':
              await showUnitWeightDialog(context, name: name, code: meal.code);
              _refresh();
            case 'delete':
              await _delete(meal);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            child: Text(mine ? s.myFoodsEdit : s.myFoodsEditAsMine),
          ),
          PopupMenuItem(value: 'unit', child: Text(s.unitWeightChange)),
          if (mine)
            PopupMenuItem(
              value: 'delete',
              child: Text(
                MaterialLocalizations.of(context).deleteButtonTooltip,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final mine = _mine();
    final mineNames = {for (final m in mine) FoodKnowledge.fold(m.name ?? '')};
    final database = _database(mineNames);
    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(
        top: Dimens.spacing16,
        bottom: Dimens.spacing4,
      ),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.myFoodsTitle)),
      floatingActionButton: Semantics(
        identifier: 'my-foods-new',
        child: FloatingActionButton.extended(
          onPressed: () => _edit(MealEntity.empty()),
          icon: const Icon(Icons.add_rounded),
          label: Text(s.myFoodsNew),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          Dimens.spacing8,
          Dimens.spacing16,
          96,
        ),
        children: [
          Text(s.myFoodsIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Dimens.spacing12),
          Semantics(
            identifier: 'my-foods-search',
            child: TextField(
              controller: _query,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: s.myFoodsSearch,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          header(s.myFoodsMine('${mine.length}')),
          if (mine.isEmpty)
            Text(
              s.myFoodsNoneYet,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          for (final m in mine) _tile(m, mine: true),
          if (_query.text.trim().length >= 2) ...[
            header(s.myFoodsDatabase),
            if (database.isEmpty)
              Text(
                s.myFoodsNoResults,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            for (final m in database) _tile(m, mine: false),
          ],
        ],
      ),
    );
  }
}
