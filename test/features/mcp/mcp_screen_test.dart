import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/features/mcp/data/mcp_controller.dart';
import 'package:opennutritracker/features/mcp/presentation/mcp_screen.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../points/points_test_support.dart';

class _FakeSecure extends Fake implements FlutterSecureStorage {}

class _FakeRecipes extends Fake implements RecipeDataSource {}

class _FakeIntakes extends Fake implements GetIntakeUsecase {}

/// A controller that looks like a running server and records decisions.
class _RunningController extends McpController {
  final List<McpProposal> pending;
  final approved = <String>[];
  final rejected = <String>[];

  _RunningController._(FakeHiveDBProvider db, this.pending)
    : super(
        db,
        PlannerDataSource(db),
        FakeGetPointsBudgetUsecase(PointsSettingsDataSource(db)),
        FakeGetMealPointsUsageUsecase(),
        _FakeIntakes(),
        _FakeRecipes(),
        HouseholdStore(db, _FakeSecure()),
      );

  factory _RunningController(List<McpProposal> pending) => _RunningController._(
    FakeHiveDBProvider(pointsSettingsBox: MemoryStringBox()),
    pending,
  );

  @override
  bool get isRunning => true;

  @override
  int? get port => 8765;

  @override
  List<McpProposal> proposals() => [
    for (final p in pending)
      if (!approved.contains(p.id) && !rejected.contains(p.id)) p,
  ];

  @override
  Future<void> approve(String id) async {
    approved.add(id);
    revision.value++;
  }

  @override
  Future<void> reject(String id) async {
    rejected.add(id);
    revision.value++;
  }
}

void main() {
  final proposals = [
    McpProposal(
      id: 'p1',
      kind: McpProposalKind.addDish,
      createdAt: DateTime(2026, 12, 1),
      data: const {
        'date': '2026-12-02',
        'meal': 'lunch',
        'amount': 130.0,
        'unit': 'g',
        'name': 'Salmon',
      },
    ),
    McpProposal(
      id: 'p2',
      kind: McpProposalKind.tickItem,
      createdAt: DateTime(2026, 12, 1),
      data: const {'week': '2026-11-30', 'key': 'k', 'name': 'Milk'},
    ),
  ];

  Future<_RunningController> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = _RunningController(proposals);
    await controller.saveConfig(
      const McpConfig(enabled: true, token: 'tok123'),
    );
    await tester.pumpWidget(
      localizedApp(
        McpScreen(
          controller: controller,
          lanAddresses: () async => ['192.168.1.5'],
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('shows the address and hides the token until revealed', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('http://192.168.1.5:8765/mcp'), findsOneWidget);
    expect(find.text('tok123'), findsNothing);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(find.text('tok123'), findsOneWidget);
  });

  testWidgets('copy config puts the client JSON with the token on the '
      'clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(tester);
    await tester.tap(bySemanticsId('mcp-copy-config'));
    await tester.pumpAndSettle();
    final json = jsonDecode(copied!) as Map<String, dynamic>;
    final server = json['mcpServers']['eatpoint'];
    expect(server['url'], 'http://192.168.1.5:8765/mcp');
    expect(server['headers']['Authorization'], 'Bearer tok123');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('shows proposals and calls approve and reject', (tester) async {
    final controller = await pump(tester);
    expect(find.textContaining('Add Salmon (130 g) to Lunch'), findsOneWidget);
    expect(find.text('Tick off Milk on the shopping list'), findsOneWidget);

    await tester.tap(bySemanticsId('mcp-approve-p1'));
    await tester.pumpAndSettle();
    expect(controller.approved, ['p1']);

    await tester.tap(bySemanticsId('mcp-reject-p2'));
    await tester.pumpAndSettle();
    expect(controller.rejected, ['p2']);
    expect(find.text('No proposals'), findsOneWidget);
  });

  testWidgets('the diary switch saves the config', (tester) async {
    final controller = await pump(tester);
    expect(controller.getConfig().allowDiary, isFalse);
    await tester.ensureVisible(bySemanticsId('mcp-allow-diary'));
    await tester.tap(bySemanticsId('mcp-allow-diary'));
    await tester.pumpAndSettle();
    expect(controller.getConfig().allowDiary, isTrue);
  });
}
