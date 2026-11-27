import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/domain/shopping_list_builder.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_auto_sync.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/features/travel/presentation/travel_mode_banner.dart';
import 'package:opennutritracker/features/food_knowledge/domain/portion_formatter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// The shopping list of one week, built from the week's plans.
class ShoppingListScreen extends StatefulWidget {
  final DateTime weekOf;

  /// Injected by tests; the app uses [SharePlus.instance].
  final SharePlus? sharePlus;

  const ShoppingListScreen({super.key, required this.weekOf, this.sharePlus});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  static const _defaultOwner = 'me';

  final _source = locator<PlannerDataSource>();

  /// EatPoint household: the other members' menus feed a joint list.
  final HouseholdStore? _household = locator.isRegistered<HouseholdStore>()
      ? locator<HouseholdStore>()
      : null;
  bool _jointView = true;
  bool _shared = false;
  String _owner = _defaultOwner;

  List<ShoppingItem> _items = const [];
  ShoppingListState _state = const ShoppingListState();

  @override
  void initState() {
    super.initState();
    _source.revision.addListener(_load);
    _household?.revision.addListener(_load);
    HouseholdAutoSync.instance.attach();
    _load();
  }

  @override
  void dispose() {
    _source.revision.removeListener(_load);
    _household?.revision.removeListener(_load);
    HouseholdAutoSync.instance.detach();
    super.dispose();
  }

  List<({MealEntity meal, double grams})>? _ingredientsOf(
    MealEntity recipeMeal,
    double dishGrams,
  ) {
    final id = recipeMeal.code;
    if (id == null) return null;
    final dbo = locator<RecipeDataSource>().getRecipeById(id);
    if (dbo == null) return null;
    final recipe = RecipeEntity.fromDBO(dbo);
    if (recipe.totalWeightG <= 0) return null;
    final factor = dishGrams / recipe.totalWeightG;
    return [
      for (final i in recipe.ingredients)
        (meal: i.snapshotMeal, grams: i.convertedAmountG * factor),
    ];
  }

  void _load() {
    final plans = _source.getWeek(widget.weekOf);
    final household = _household?.getHousehold();
    final others = household == null
        ? const <MemberSnapshot>[]
        : _household!.otherMembers();
    final myName = household?.memberName ?? '';
    _owner = myName.isEmpty ? _defaultOwner : myName;
    _shared = others.isNotEmpty;
    final start = DayPlan.weekStart(widget.weekOf);
    final built = ShoppingListBuilder.build([
      for (final p in plans) (owner: _owner, plan: p),
      if (_jointView)
        for (final m in others)
          for (var i = 0; i < 7; i++)
            if (m.dayFor(start.add(Duration(days: i))) case final d?)
              (owner: m.name.isEmpty ? m.memberId : m.name, plan: d),
    ], recipeIngredients: _ingredientsOf);
    final state = _source.getShopping(widget.weekOf);
    final keys = built.map((i) => i.key).toSet();
    final items = [
      ...built,
      ...state.manualItems.where((m) => !keys.contains(m.key)),
    ];
    items.sort((a, b) {
      final byAisle = a.aisle.index.compareTo(b.aisle.index);
      return byAisle != 0
          ? byAisle
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (!mounted) return;
    setState(() {
      _items = items;
      _state = state;
    });
  }

  String _aisleName(ShoppingAisle aisle) {
    final s = S.of(context);
    switch (aisle) {
      case ShoppingAisle.produce:
        return s.shoppingAisleProduce;
      case ShoppingAisle.meatFish:
        return s.shoppingAisleMeatFish;
      case ShoppingAisle.dairyEggs:
        return s.shoppingAisleDairyEggs;
      case ShoppingAisle.bakery:
        return s.shoppingAisleBakery;
      case ShoppingAisle.pantry:
        return s.shoppingAislePantry;
      case ShoppingAisle.drinks:
        return s.shoppingAisleDrinks;
      case ShoppingAisle.other:
        return s.shoppingAisleOther;
    }
  }

  String _amountText(ShoppingItem item) {
    if (item.amount <= 0) return '';
    final format = PointsFormat.of(context);
    final unit = item.unit;
    if (unit == 'g' && item.amount >= 1000) {
      return '${format.grams((item.amount / 100).round() / 10)} kg';
    }
    if (unit == 'ml' && item.amount >= 1000) {
      return '${format.grams((item.amount / 100).round() / 10)} l';
    }
    final rounded = format.grams(item.amount.roundToDouble());
    return unit.isEmpty ? rounded : '$rounded $unit';
  }

  /// "≈ 6 patatas" under an item bought by the piece.
  String? _piecesText(ShoppingItem item) {
    if (item.unit != 'g' && item.unit != 'ml') return null;
    final pieces = PortionFormatter.forShopping(item.name, item.amount);
    if (pieces == null) return null;
    return '≈ ${pieces.label(Localizations.localeOf(context).languageCode)}';
  }

  Future<void> _save(ShoppingListState next) async {
    setState(() => _state = next);
    await _source.saveShopping(widget.weekOf, next);
  }

  Future<void> _addItem() async {
    final result = await showDialog<({String name, String amount})>(
      context: context,
      builder: (context) => const _AddItemDialog(),
    );
    if (result == null || !mounted) return;
    final text = result.name.trim();
    final amountText = result.amount;
    if (text.isEmpty) return;
    final key = 'manual|${ShoppingListBuilder.normalise(text)}';
    if (_items.any((i) => i.key == key)) return;
    final parsed = _parseAmount(amountText);
    final item = ShoppingItem(
      key: key,
      name: text,
      amount: parsed.amount,
      unit: parsed.unit,
      aisle: ShoppingListBuilder.aisleFor(text),
      manual: true,
    );
    await _save(_state.addManual(item));
    _load();
  }

  /// "500", "2 kg", "1,5 l": a number with an optional unit.
  ({double amount, String unit}) _parseAmount(String text) {
    final match = RegExp(
      r'^\s*([0-9]+(?:[.,][0-9]+)?)\s*([a-zA-Z]*)\s*$',
    ).firstMatch(text);
    if (match == null) return (amount: 0, unit: '');
    var value = PointsFormat.parse(match.group(1)!) ?? 0;
    var unit = match.group(2)!.toLowerCase();
    if (unit == 'kg') {
      value *= 1000;
      unit = 'g';
    } else if (unit == 'l') {
      value *= 1000;
      unit = 'ml';
    }
    return (amount: value, unit: unit);
  }

  Future<void> _removeManual(ShoppingItem item) async {
    await _save(_state.removeManual(item.key));
    _load();
  }

  Future<void> _export() async {
    final s = S.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              identifier: 'shopping-export-text',
              child: ListTile(
                leading: const Icon(Icons.text_snippet_outlined),
                title: Text(s.shoppingExportText),
                onTap: () => Navigator.pop(context, 'text'),
              ),
            ),
            Semantics(
              identifier: 'shopping-export-csv',
              child: ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: Text(s.shoppingExportCsv),
                onTap: () => Navigator.pop(context, 'csv'),
              ),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final share = widget.sharePlus ?? SharePlus.instance;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    if (choice == 'text') {
      final text = ShoppingListBuilder.toText(
        _items,
        _state.checked,
        aisleName: _aisleName,
        amountText: _amountText,
      );
      await share.share(ShareParams(text: text, sharePositionOrigin: origin));
    } else {
      final csv = ShoppingListBuilder.toCsv(
        _items,
        _state.checked,
        aisleName: _aisleName,
        header: s.shoppingCsvHeader.split(','),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/shopping-list.csv');
      await file.writeAsString(csv);
      await share.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          sharePositionOrigin: origin,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final weekStart = DayPlan.weekStart(widget.weekOf);
    final done = _items.where((i) => _state.checked.contains(i.key)).length;
    final total = _items.length;

    final children = <Widget>[];
    if (_shared) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            0,
          ),
          child: Semantics(
            identifier: 'shopping-joint-toggle',
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(s.shoppingJoint)),
                ButtonSegment(value: false, label: Text(s.shoppingMineOnly)),
              ],
              selected: {_jointView},
              onSelectionChanged: (v) {
                setState(() => _jointView = v.first);
                _load();
              },
            ),
          ),
        ),
      );
    }
    if (total > 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            Dimens.spacing8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: Dimens.borderRadiusS,
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: done / total,
                ),
              ),
              const SizedBox(height: Dimens.spacing8),
              Text(
                s.shoppingProgress(done.toString(), total.toString()),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    ShoppingAisle? current;
    for (final item in _items) {
      if (item.aisle != current) {
        current = item.aisle;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing16,
              Dimens.spacing16,
              Dimens.spacing16,
              Dimens.spacing4,
            ),
            child: Text(
              _aisleName(item.aisle),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      children.add(_row(item, theme));
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.shoppingTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              s.shoppingWeek(DateFormat.MMMd(locale).format(weekStart)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          Semantics(
            identifier: 'shopping-export',
            child: IconButton(
              tooltip: s.shoppingExport,
              icon: const Icon(Icons.ios_share),
              onPressed: _items.isEmpty ? null : _export,
            ),
          ),
        ],
      ),
      floatingActionButton: Semantics(
        identifier: 'shopping-add-item',
        child: FloatingActionButton.extended(
          onPressed: _addItem,
          icon: const Icon(Icons.add),
          label: Text(s.shoppingAddItem),
        ),
      ),
      body: Column(
        children: [
          if (TravelModeGate.plannerPaused) const TravelModeBanner(),
          Expanded(child: _body(context, total, children)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, int total, List<Widget> children) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return total == 0
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing32),
                child: Text(
                  s.shoppingEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            )
          : Semantics(
              identifier: 'shopping-list',
              container: true,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: children,
              ),
            );
  }

  Widget _row(ShoppingItem item, ThemeData theme) {
    final s = S.of(context);
    final checked = _state.checked.contains(item.key);
    final by = _state.checkedBy[item.key];
    final format = PointsFormat.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final subtitleLines = <String>[
      ?_piecesText(item),
      if (item.perOwner.length > 1)
        item.perOwner.entries
            .map((e) => '${e.key}: ${format.grams(e.value.roundToDouble())}')
            .join(' · '),
      if (checked && by != null && by != _owner) s.shoppingTickedBy(by),
    ];
    final amount = _amountText(item);
    return GestureDetector(
      onLongPress: item.manual ? () => _removeManual(item) : null,
      child: CheckboxListTile(
        key: ValueKey(item.key),
        controlAffinity: ListTileControlAffinity.leading,
        value: checked,
        onChanged: (_) => _save(_state.toggle(item.key, by: _owner)),
        title: Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: checked
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: muted.withValues(alpha: 0.7),
                )
              : null,
        ),
        subtitle: subtitleLines.isEmpty ? null : Text(subtitleLines.join('\n')),
        secondary: amount.isEmpty
            ? null
            : Text(
                amount,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: checked ? muted.withValues(alpha: 0.7) : null,
                  decoration: checked ? TextDecoration.lineThrough : null,
                ),
              ),
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog();

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _name = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(s.shoppingAddItem),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            identifier: 'shopping-add-name',
            child: TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: s.shoppingItemName),
            ),
          ),
          const SizedBox(height: Dimens.spacing12),
          Semantics(
            identifier: 'shopping-add-amount',
            child: TextField(
              controller: _amount,
              decoration: InputDecoration(labelText: s.shoppingItemAmount),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(material.cancelButtonLabel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, (name: _name.text, amount: _amount.text)),
          child: Text(material.okButtonLabel),
        ),
      ],
    );
  }
}
