import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/data/dbo/favourite_meal_dbo.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/features/mcp/data/mcp_controller.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../planner/planner_test_support.dart';
import '../points/points_test_support.dart';

class _KeyedStringBox extends MemoryStringBox {
  @override
  Iterable<dynamic> get keys => data.keys;
}

class _NoFavourites extends Fake implements Box<FavouriteMealDBO> {
  @override
  Iterable<FavouriteMealDBO> get values => const [];
}

class _NoRecipes extends Fake implements RecipeDataSource {
  @override
  List<RecipeDBO> getAllRecipes() => const [];
}

class _FakeSecure extends Fake implements FlutterSecureStorage {}

class _FakeIntakes extends Fake implements GetIntakeUsecase {
  final List<IntakeEntity> recent;
  _FakeIntakes(this.recent);

  @override
  Future<List<IntakeEntity>> getRecentIntake() async => recent;
}

void main() {
  late PlannerDataSource planner;
  late McpController controller;
  final day = DateTime(2026, 12, 2);

  setUp(() {
    final db = FakeHiveDBProvider(
      pointsSettingsBox: _KeyedStringBox(),
      favouriteMealBox: _NoFavourites(),
    );
    planner = PlannerDataSource(db);
    final budget = FakeGetPointsBudgetUsecase(PointsSettingsDataSource(db));
    controller = McpController(
      db,
      planner,
      budget,
      FakeGetMealPointsUsageUsecase(),
      _FakeIntakes([
        IntakeEntity(
          id: 'i1',
          unit: 'g',
          amount: 150,
          type: IntakeTypeEntity.lunch,
          meal: plannerMeal('Salmon'),
          dateTime: day,
        ),
      ]),
      _NoRecipes(),
      HouseholdStore(db, _FakeSecure()),
    );
  });

  tearDown(() => controller.stop());

  Future<void> start({bool allowDiary = false}) async {
    await controller.saveConfig(
      McpConfig(enabled: true, allowDiary: allowDiary, port: 0),
    );
    await controller.applyConfig();
  }

  var nextId = 0;
  Future<Map<String, dynamic>> rpc(String method, [Object? params]) async {
    final res = await http.post(
      Uri.parse('http://127.0.0.1:${controller.port}/mcp'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${controller.getConfig().token}',
      },
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': ++nextId,
        'method': method,
        'params': ?params,
      }),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<({bool isError, String text})> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) async {
    final result =
        (await rpc('tools/call', {'name': tool, 'arguments': args}))['result']
            as Map<String, dynamic>;
    return (
      isError: result['isError'] as bool,
      text: result['content'][0]['text'] as String,
    );
  }

  test('config round-trips and defaults to disabled', () async {
    expect(controller.getConfig().enabled, isFalse);
    expect(controller.getConfig().allowDiary, isFalse);
    await controller.saveConfig(
      const McpConfig(enabled: true, token: 't', allowDiary: true, port: 9000),
    );
    final config = controller.getConfig();
    expect(config.enabled, isTrue);
    expect(config.token, 't');
    expect(config.allowDiary, isTrue);
    expect(config.port, 9000);
  });

  test('applyConfig generates a token, starts, and stop stops', () async {
    await start();
    expect(controller.isRunning, isTrue);
    expect(controller.port, isNotNull);
    expect(controller.getConfig().token, isNotEmpty);
    await controller.stop();
    expect(controller.isRunning, isFalse);
  });

  test('get_week_menu returns the planned day', () async {
    await planner.saveDay(
      dayPlan(day, {
        IntakeTypeEntity.lunch: [plannedItem('Soup', 200)],
      }),
    );
    await start();
    final res = await call('get_week_menu', {'week_of': '2026-12-02'});
    expect(res.isError, isFalse);
    final json = jsonDecode(res.text);
    final days = json['days'] as List;
    final planned = days.firstWhere((d) => d['date'] == '2026-12-02');
    expect(planned['meals']['lunch']['items'][0]['name'], 'Soup');
  });

  test('search_my_dishes finds the logged meal', () async {
    await start();
    final res = await call('search_my_dishes', {'query': 'salm'});
    final list = jsonDecode(res.text) as List;
    expect(list.single['name'], 'Salmon');
    expect(list.single['usual_amount'], 150);
  });

  test('propose_add_dish creates a proposal and approve plans it', () async {
    await start();
    final res = await call('propose_add_dish', {
      'date': '2026-12-02',
      'meal': 'dinner',
      'dish_name': 'Salmon',
      'amount': 120,
    });
    expect(res.isError, isFalse);
    final proposals = controller.proposals();
    expect(proposals.single.kind, McpProposalKind.addDish);
    expect(planner.getDay(day).itemsFor('dinner'), isEmpty);

    await controller.approve(proposals.single.id);
    final items = planner.getDay(day).itemsFor('dinner');
    expect(items.single.name, 'Salmon');
    expect(items.single.amount, 120);
    expect(controller.proposals(), isEmpty);
  });

  test('propose_tick_item then approve ticks the item', () async {
    await planner.saveDay(
      dayPlan(day, {
        IntakeTypeEntity.lunch: [plannedItem('Soup', 200)],
      }),
    );
    await start();
    final res = await call('propose_tick_item', {
      'item_name': 'soup',
      'week_of': '2026-12-02',
    });
    expect(res.isError, isFalse);
    final proposal = controller.proposals().single;
    expect(proposal.kind, McpProposalKind.tickItem);
    await controller.approve(proposal.id);
    expect(
      planner.getShopping(day).checked,
      contains(proposal.data['key'] as String),
    );
  });

  test('reject removes the proposal without changing the plan', () async {
    await start();
    await call('propose_add_dish', {
      'date': '2026-12-02',
      'meal': 'lunch',
      'dish_name': 'Salmon',
    });
    await controller.reject(controller.proposals().single.id);
    expect(controller.proposals(), isEmpty);
    expect(planner.getDay(day).isEmpty, isTrue);
  });

  test('get_day_log is only listed when allowDiary is on', () async {
    Future<List<String>> names() async {
      final r = await rpc('tools/list');
      return [for (final t in r['result']['tools'] as List) t['name']];
    }

    await start();
    expect(await names(), isNot(contains('get_day_log')));
    await start(allowDiary: true);
    final enabled = await names();
    expect(enabled, contains('get_day_log'));
    final res = await call('get_day_log', {'date': '2026-12-02'});
    expect(res.isError, isFalse);
    expect(jsonDecode(res.text), contains('lunch'));
  });

  test('an unknown dish is a tool error with guidance', () async {
    await start();
    final res = await call('propose_add_dish', {
      'date': '2026-12-02',
      'meal': 'lunch',
      'dish_name': 'Moon cheese',
    });
    expect(res.isError, isTrue);
    expect(res.text, contains('search_my_dishes'));
    expect(controller.proposals(), isEmpty);
  });

  test('get_points_budget returns the daily budget', () async {
    await start();
    final res = await call('get_points_budget');
    expect(res.isError, isFalse);
    expect(jsonDecode(res.text)['daily'], contains('total'));
  });
}
