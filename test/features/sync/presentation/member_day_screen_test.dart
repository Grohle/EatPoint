import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/food_knowledge/domain/food_knowledge.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_menu.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:opennutritracker/features/sync/presentation/member_day_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../helpers/fake_hive_db_provider.dart';
import '../../planner/planner_test_support.dart';

class _MemoryStorage implements FlutterSecureStorage {
  final store = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store[key];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Box extends MemoryStringBox {
  @override
  Iterable<dynamic> get keys => data.keys;
}

void main() {
  final day = DateTime(2026, 11, 30);
  late HouseholdStore store;

  setUp(() async {
    await locator.reset();
    FoodKnowledge.setInstance(
      FoodKnowledge.parse(File(FoodKnowledge.assetPath).readAsStringSync()),
    );
    store = HouseholdStore(
      FakeHiveDBProvider(pointsSettingsBox: _Box()),
      _MemoryStorage(),
    );
    await store.saveHousehold(
      const Household(
        householdId: '0123456789abcdef0123456789abcdef',
        memberId: 'aaaaaaaaaaaaaaaa',
        memberName: 'Ann',
        backend: SyncBackendConfig(
          kind: SyncBackendKind.webdav,
          url: 'https://example.org/dav',
        ),
      ),
    );
  });

  Future<void> addBo({required bool allowEdits}) => store.saveMember(
    MemberSnapshot(
      memberId: 'bbbbbbbbbbbbbbbb',
      name: 'Bo',
      updatedAt: day,
      days: [
        dayPlan(day, {
          'lunch': [plannedItem('Lentils', 200), plannedItem('Bread', 40)],
        }),
      ],
      profile: MemberProfile(
        slots: const [
          MemberSlot(id: 'lunch', baseType: IntakeTypeEntity.lunch),
        ],
        budgets: const {'lunch': MacroPoints(carbs: 4, protein: 3, fat: 2)},
        allowEdits: allowEdits,
      ),
    ),
  );

  Widget screen() => localizedApp(
    MemberDayScreen(memberId: 'bbbbbbbbbbbbbbbb', date: day, store: store),
  );

  testWidgets('another member\'s meal can be changed when they allow it', (
    tester,
  ) async {
    await addBo(allowEdits: true);
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Lentils'), findsOneWidget);

    await tester.tap(bySemanticsId('member-day-edit-lunch'));
    await tester.pumpAndSettle();
    final s = S.of(tester.element(find.byType(Scaffold).last));
    await tester.tap(find.byTooltip(s.plannerRemoveItem).last);
    await tester.pump();
    await tester.tap(bySemanticsId('meal-editor-save'));
    await tester.pumpAndSettle();

    final edit = store.pendingEdits().single;
    expect(edit.memberId, 'bbbbbbbbbbbbbbbb');
    expect(edit.by, 'Ann');
    expect(edit.items.map((i) => i.name), ['Lentils']);
    expect(find.text('Bread'), findsNothing, reason: 'shown at once');
  });

  testWidgets('a member who doesn\'t allow it can only be looked at', (
    tester,
  ) async {
    await addBo(allowEdits: false);
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    final s = S.of(tester.element(find.byType(MemberDayScreen)));
    expect(find.text(s.householdMemberNoEdits('Bo')), findsOneWidget);
    expect(bySemanticsId('member-day-edit-lunch'), findsNothing);
  });
}
