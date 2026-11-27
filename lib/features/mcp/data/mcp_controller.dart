import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/mcp/domain/mcp_server.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/planner/domain/shopping_list_builder.dart';
import 'package:opennutritracker/features/points/domain/points_extensions.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_meal_points_usage_usecase.dart';
import 'package:opennutritracker/features/points/domain/usecase/get_points_budget_usecase.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';

/// Connector settings, kept in EatPoint's per-profile box.
class McpConfig {
  final bool enabled;
  final String token;
  final bool allowDiary;
  final int port;

  const McpConfig({
    this.enabled = false,
    this.token = '',
    this.allowDiary = false,
    this.port = 8765,
  });

  McpConfig copyWith({
    bool? enabled,
    String? token,
    bool? allowDiary,
    int? port,
  }) => McpConfig(
    enabled: enabled ?? this.enabled,
    token: token ?? this.token,
    allowDiary: allowDiary ?? this.allowDiary,
    port: port ?? this.port,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'token': token,
    'allowDiary': allowDiary,
    'port': port,
  };

  static McpConfig fromJson(Object? json) {
    if (json is! Map) return const McpConfig();
    return McpConfig(
      enabled: json['enabled'] == true,
      token: json['token'] as String? ?? '',
      allowDiary: json['allowDiary'] == true,
      port: json['port'] is int ? json['port'] as int : 8765,
    );
  }
}

enum McpProposalKind { addDish, tickItem }

/// A change an agent asked for, waiting for the user.
class McpProposal {
  final String id;
  final McpProposalKind kind;
  final DateTime createdAt;

  /// addDish: date, meal, amount, unit, meal snapshot (MealDBO JSON).
  /// tickItem: week (yyyy-mm-dd), key, name.
  final Map<String, dynamic> data;

  const McpProposal({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'data': data,
  };

  static McpProposal? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = McpProposalKind.values.where((k) => k.name == json['kind']);
    final data = json['data'];
    if (kind.isEmpty || data is! Map) return null;
    return McpProposal(
      id: json['id'] as String? ?? '',
      kind: kind.first,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      data: Map<String, dynamic>.from(data),
    );
  }
}

/// Runs the on-phone MCP server and owns its tools and proposals.
class McpController {
  static const _configKey = 'mcp:config';
  static const _proposalsKey = 'mcp:proposals';
  static const maxProposals = 50;

  final _log = Logger('McpController');
  final HiveDBProvider _db;
  final PlannerDataSource _planner;
  final GetPointsBudgetUsecase _budget;
  final GetMealPointsUsageUsecase _usage;
  final GetIntakeUsecase _intakes;
  final RecipeDataSource _recipes;
  final HouseholdStore _household;

  McpServer? _server;

  /// Bumped when the config, the server state or the proposals change.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  McpController(
    this._db,
    this._planner,
    this._budget,
    this._usage,
    this._intakes,
    this._recipes,
    this._household,
  );

  bool get isRunning => _server?.isRunning ?? false;

  McpConfig getConfig() {
    final raw = _db.pointsSettingsBox.get(_configKey);
    if (raw == null) return const McpConfig();
    try {
      return McpConfig.fromJson(jsonDecode(raw));
    } on FormatException {
      return const McpConfig();
    }
  }

  Future<void> saveConfig(McpConfig config) async {
    await _db.pointsSettingsBox.put(_configKey, jsonEncode(config.toJson()));
    revision.value++;
  }

  /// Starts or stops the server to match the stored config. Call when the
  /// app comes to the foreground and after the user changes the switch.
  Future<void> applyConfig() async {
    var config = getConfig();
    if (!config.enabled) {
      await stop();
      return;
    }
    if (config.token.isEmpty) {
      config = config.copyWith(token: McpServer.generateToken());
      await saveConfig(config);
    }
    if (_server?.token == config.token && isRunning) return;
    await stop();
    final server = McpServer(token: config.token, tools: _tools);
    try {
      await server.start(port: config.port);
    } on SocketException {
      // The preferred port is taken: let the system pick one.
      await server.start(port: 0);
    }
    _server = server;
    revision.value++;
  }

  Future<void> stop() async {
    await _server?.stop();
    _server = null;
    revision.value++;
  }

  int? get port => _server?.port;

  /// The phone's Wi-Fi / LAN IPv4 addresses.
  static Future<List<String>> lanAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (a.isLinkLocal == false) a.address,
    ];
  }

  /// A JSON snippet most MCP clients accept for a remote HTTP server.
  static String clientConfig(String url, String token) =>
      const JsonEncoder.withIndent('  ').convert({
        'mcpServers': {
          'eatpoint': {
            'type': 'http',
            'url': url,
            'headers': {'Authorization': 'Bearer $token'},
          },
        },
      });

  // --- proposals -------------------------------------------------------

  List<McpProposal> proposals() {
    final raw = _db.pointsSettingsBox.get(_proposalsKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.map(McpProposal.fromJson).whereType<McpProposal>().toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> _saveProposals(List<McpProposal> list) async {
    await _db.pointsSettingsBox.put(
      _proposalsKey,
      jsonEncode([for (final p in list) p.toJson()]),
    );
    revision.value++;
  }

  Future<McpProposal> _propose(
    McpProposalKind kind,
    Map<String, dynamic> data,
  ) async {
    final list = proposals();
    if (list.length >= maxProposals) {
      throw McpToolError(
        'There are already $maxProposals proposals waiting for the user.',
      );
    }
    final proposal = McpProposal(
      id: IdGenerator.getUniqueID(),
      kind: kind,
      createdAt: DateTime.now(),
      data: data,
    );
    await _saveProposals([...list, proposal]);
    return proposal;
  }

  Future<void> reject(String id) =>
      _saveProposals(proposals().where((p) => p.id != id).toList());

  Future<void> approve(String id) async {
    final proposal = proposals().where((p) => p.id == id).firstOrNull;
    if (proposal == null) return;
    switch (proposal.kind) {
      case McpProposalKind.addDish:
        final date = DateTime.parse(proposal.data['date'] as String);
        final type = IntakeTypeEntity.values.byName(
          proposal.data['meal'] as String,
        );
        final meal = MealEntity.fromMealDBO(
          MealDBO.fromJson(
            Map<String, dynamic>.from(proposal.data['food'] as Map),
          ),
        );
        final day = _planner.getDay(date);
        await _planner.saveDay(
          day.withMeal(type, [
            ...day.itemsFor(type),
            PlannedItem(
              id: IdGenerator.getUniqueID(),
              meal: meal,
              amount: (proposal.data['amount'] as num).toDouble(),
              unit: proposal.data['unit'] as String? ?? 'g',
            ),
          ]),
        );
      case McpProposalKind.tickItem:
        final week = DateTime.parse(proposal.data['week'] as String);
        final key = proposal.data['key'] as String;
        final state = _planner.getShopping(week);
        if (!state.checked.contains(key)) {
          await _planner.saveShopping(week, state.toggle(key));
        }
    }
    await reject(id);
  }

  // --- tools -----------------------------------------------------------

  static Map<String, dynamic> _points(MacroPoints p) => {
    'carbs': PointsCalc.roundTo(p.carbs, 2),
    'protein': PointsCalc.roundTo(p.protein, 2),
    'fat': PointsCalc.roundTo(p.fat, 2),
    'total': PointsCalc.roundTo(p.total, 2),
  };

  static DateTime _dateArg(Map<String, dynamic> args, String name) {
    final raw = args[name];
    if (raw == null) return DateTime.now();
    final parsed = raw is String ? DateTime.tryParse(raw) : null;
    if (parsed == null) {
      throw McpToolError('$name must be a date like 2026-12-01');
    }
    return parsed;
  }

  static IntakeTypeEntity _mealArg(Map<String, dynamic> args) {
    final raw = args['meal'];
    for (final t in IntakeTypeEntity.values) {
      if (t.name == raw) return t;
    }
    throw McpToolError('meal must be one of breakfast, lunch, snack, dinner');
  }

  Map<String, dynamic> _dayJson(DayPlan day) => {
    'date': DayPlan.dateKey(day.date),
    'meals': {
      for (final type in IntakeTypeEntity.values)
        type.name: {
          'logged': day.logged.contains(type),
          'points': _points(day.pointsFor(type)),
          'items': [
            for (final item in day.itemsFor(type))
              {
                'name': item.name,
                'amount': item.amount.round(),
                'unit': item.unit,
                'points': _points(item.points),
              },
          ],
        },
    },
  };

  Future<List<({MealEntity meal, double amount})>> _pastDishes() async {
    final dishes = <String, ({MealEntity meal, double amount})>{};
    String key(MealEntity m) => ShoppingListBuilder.normalise(m.name ?? '');
    try {
      for (final intake in await _intakes.getRecentIntake()) {
        final k = key(intake.meal);
        if (k.isNotEmpty) {
          dishes.putIfAbsent(
            k,
            () => (meal: intake.meal, amount: intake.amount),
          );
        }
      }
    } catch (e) {
      _log.fine('recent intakes unavailable: $e');
    }
    for (final dbo in _recipes.getAllRecipes()) {
      final recipe = RecipeEntity.fromDBO(dbo);
      final servings = recipe.servingsCount;
      final amount = servings != null && servings > 0
          ? recipe.totalWeightG / servings
          : recipe.totalWeightG;
      dishes.putIfAbsent(
        'recipe:${recipe.id}',
        () => (meal: recipe.toMealEntity(), amount: amount > 0 ? amount : 100),
      );
    }
    for (final fav in _db.favouriteMealBox.values) {
      final meal = MealEntity.fromMealDBO(fav.meal);
      final k = key(meal);
      if (k.isNotEmpty) {
        dishes.putIfAbsent(
          k,
          () => (meal: meal, amount: meal.scalableServingQuantity ?? 100),
        );
      }
    }
    return dishes.values.where((d) => d.meal.pointsPer100 != null).toList();
  }

  List<McpTool> _tools() {
    final config = getConfig();
    return [
      McpTool(
        name: 'get_points_budget',
        description:
            'The user\'s daily points budget and its split per meal, in '
            'carb, protein and fat points (1 point = 100 kcal).',
        inputSchema: const {'type': 'object', 'properties': {}},
        handler: (_) async {
          final b = await _budget.getBudget();
          return {
            'daily': _points(b.daily),
            'kcal_goal': b.suggestion.kcalGoal.round(),
            'per_meal': {
              for (final e in b.perMeal.entries) e.key.name: _points(e.value),
            },
            'note': 'A guide only; the user can change it in the app.',
          };
        },
      ),
      McpTool(
        name: 'get_week_menu',
        description:
            'The planned menu for the week (Monday to Sunday) containing '
            'week_of, with each dish\'s amount and points, plus the other '
            'household members\' menus when the household is shared.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'week_of': {
              'type': 'string',
              'description': 'Any date in the week, YYYY-MM-DD. Default today.',
            },
          },
        },
        handler: (args) async {
          final weekOf = _dateArg(args, 'week_of');
          final start = DayPlan.weekStart(weekOf);
          return {
            'week_start': DayPlan.dateKey(start),
            'days': [for (final d in _planner.getWeek(weekOf)) _dayJson(d)],
            'other_members': [
              for (final m in _household.otherMembers())
                {
                  'name': m.name,
                  'days': [
                    for (var i = 0; i < 7; i++)
                      if (m.dayFor(start.add(Duration(days: i))) case final d?)
                        _dayJson(d),
                  ],
                },
            ],
          };
        },
      ),
      McpTool(
        name: 'get_shopping_list',
        description:
            'The shopping list for the week containing week_of, built from '
            'the planned menus (joint list when the household is shared), '
            'with what is already ticked off.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'week_of': {'type': 'string', 'description': 'YYYY-MM-DD'},
          },
        },
        handler: (args) async {
          final weekOf = _dateArg(args, 'week_of');
          final start = DayPlan.weekStart(weekOf);
          final items = ShoppingListBuilder.build([
            for (final d in _planner.getWeek(weekOf)) (owner: 'me', plan: d),
            for (final m in _household.otherMembers())
              for (var i = 0; i < 7; i++)
                if (m.dayFor(start.add(Duration(days: i))) case final d?)
                  (owner: m.name, plan: d),
          ]);
          final state = _planner.getShopping(weekOf);
          return {
            'week_start': DayPlan.dateKey(start),
            'items': [
              for (final i in [...items, ...state.manualItems])
                {
                  'name': i.name,
                  'amount': i.amount.round(),
                  'unit': i.unit,
                  'aisle': i.aisle.name,
                  'ticked': state.checked.contains(i.key),
                },
            ],
          };
        },
      ),
      McpTool(
        name: 'search_my_dishes',
        description:
            'Foods and recipes the user has logged or saved before, with '
            'their usual amount and points. Use these names in '
            'propose_add_dish.',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
            'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50},
          },
        },
        handler: (args) async {
          final query = ShoppingListBuilder.normalise(
            args['query'] as String? ?? '',
          );
          final limit = (args['limit'] as int? ?? 20).clamp(1, 50);
          final dishes = (await _pastDishes())
              .where(
                (d) =>
                    query.isEmpty ||
                    ShoppingListBuilder.normalise(
                      d.meal.name ?? '',
                    ).contains(query),
              )
              .take(limit);
          return [
            for (final d in dishes)
              {
                'name': d.meal.name,
                'points_per_100': PointsCalc.roundTo(d.meal.pointsPer100!, 2),
                'usual_amount': d.amount.round(),
                'unit': d.meal.isLiquid ? 'ml' : 'g',
                'usual_points': _points(
                  d.meal.nutriments.macroPointsFor(d.amount),
                ),
              },
          ];
        },
      ),
      if (config.allowDiary)
        McpTool(
          name: 'get_day_log',
          description: 'Points the user has logged per meal on a day.',
          inputSchema: const {
            'type': 'object',
            'properties': {
              'date': {'type': 'string', 'description': 'YYYY-MM-DD'},
            },
          },
          handler: (args) async {
            final date = _dateArg(args, 'date');
            return {
              for (final t in IntakeTypeEntity.values)
                t.name: _points(await _usage.usedIn(t, date)),
            };
          },
        ),
      McpTool(
        name: 'propose_add_dish',
        description:
            'Proposes adding one of the user\'s dishes (see '
            'search_my_dishes) to a meal of their menu. The user approves '
            'or rejects it in the app; nothing changes until then.',
        writes: true,
        inputSchema: const {
          'type': 'object',
          'required': ['date', 'meal', 'dish_name'],
          'properties': {
            'date': {'type': 'string', 'description': 'YYYY-MM-DD'},
            'meal': {
              'type': 'string',
              'enum': ['breakfast', 'lunch', 'snack', 'dinner'],
            },
            'dish_name': {'type': 'string'},
            'amount': {
              'type': 'number',
              'description': 'Grams or ml. Default: the usual amount.',
            },
          },
        },
        handler: (args) async {
          final date = _dateArg(args, 'date');
          final type = _mealArg(args);
          final name = ShoppingListBuilder.normalise(
            args['dish_name'] as String? ?? '',
          );
          final dishes = await _pastDishes();
          final match =
              dishes
                  .where(
                    (d) =>
                        ShoppingListBuilder.normalise(d.meal.name ?? '') ==
                        name,
                  )
                  .firstOrNull ??
              dishes
                  .where(
                    (d) => ShoppingListBuilder.normalise(
                      d.meal.name ?? '',
                    ).contains(name),
                  )
                  .firstOrNull;
          if (name.isEmpty || match == null) {
            throw McpToolError(
              'No dish called "${args['dish_name']}". Call search_my_dishes '
              'first and use one of the names it returns.',
            );
          }
          final amount = (args['amount'] as num?)?.toDouble() ?? match.amount;
          if (amount <= 0 || amount > 5000) {
            throw McpToolError('amount must be between 1 and 5000');
          }
          final proposal = await _propose(McpProposalKind.addDish, {
            'date': DayPlan.dateKey(date),
            'meal': type.name,
            'amount': amount,
            'unit': match.meal.isLiquid ? 'ml' : 'g',
            'name': match.meal.name,
            'food': MealDBO.fromMealEntity(match.meal).toJson(),
          });
          return {
            'proposal_id': proposal.id,
            'status': 'waiting for the user to approve in the app',
          };
        },
      ),
      McpTool(
        name: 'propose_tick_item',
        description:
            'Proposes ticking an item off the shopping list. The user '
            'approves it in the app.',
        writes: true,
        inputSchema: const {
          'type': 'object',
          'required': ['item_name'],
          'properties': {
            'item_name': {'type': 'string'},
            'week_of': {'type': 'string', 'description': 'YYYY-MM-DD'},
          },
        },
        handler: (args) async {
          final weekOf = _dateArg(args, 'week_of');
          final name = ShoppingListBuilder.normalise(
            args['item_name'] as String? ?? '',
          );
          final items = [
            ...ShoppingListBuilder.build([
              for (final d in _planner.getWeek(weekOf)) (owner: 'me', plan: d),
            ]),
            ..._planner.getShopping(weekOf).manualItems,
          ];
          final match = items
              .where(
                (i) => ShoppingListBuilder.normalise(i.name).contains(name),
              )
              .firstOrNull;
          if (name.isEmpty || match == null) {
            throw McpToolError('No item matching "${args['item_name']}".');
          }
          final proposal = await _propose(McpProposalKind.tickItem, {
            'week': DayPlan.dateKey(DayPlan.weekStart(weekOf)),
            'key': match.key,
            'name': match.name,
          });
          return {'proposal_id': proposal.id, 'status': 'waiting for approval'};
        },
      ),
    ];
  }
}
