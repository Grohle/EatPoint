import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/menu_generator/domain/menu_generator.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_crypto.dart';
import 'package:opennutritracker/features/sync/domain/household_menu.dart';
import 'package:opennutritracker/features/sync/domain/household_sync_service.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../planner/planner_test_support.dart';

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
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Box extends MemoryStringBox {
  @override
  Iterable<dynamic> get keys => data.keys;
}

/// The shared storage: blobs by name.
class _Cloud implements SyncBackend {
  final blobs = <String, Uint8List>{};

  @override
  SyncBackendKind get kind => SyncBackendKind.webdav;

  @override
  Future<void> testConnection() async {}

  @override
  Future<List<String>> list() async => blobs.keys.toList();

  @override
  Future<Uint8List?> get(String name) async => blobs[name];

  @override
  Future<void> put(String name, Uint8List bytes) async => blobs[name] = bytes;
}

class _Phone {
  final HouseholdStore store;
  final PlannerDataSource planner;
  final HouseholdSyncService sync;

  _Phone._(this.store, this.planner, this.sync);

  static Future<_Phone> join(
    _Cloud cloud,
    HouseholdKey key, {
    required String householdId,
    required String memberId,
    required String name,
    MemberProfile? profile,
  }) async {
    final db = FakeHiveDBProvider(pointsSettingsBox: _Box());
    final store = HouseholdStore(db, _MemoryStorage());
    final planner = PlannerDataSource(db);
    await store.writeKey(key);
    await store.saveHousehold(
      Household(
        householdId: householdId,
        memberId: memberId,
        memberName: name,
        backend: const SyncBackendConfig(
          kind: SyncBackendKind.webdav,
          url: 'https://example.org/dav',
        ),
      ),
    );
    final sync = HouseholdSyncService(
      planner,
      store,
      (config, {required householdId, required secret}) => cloud,
      profile: () async => profile,
    );
    return _Phone._(store, planner, sync);
  }
}

void main() {
  final day = DateTime(2026, 11, 30);
  late _Cloud cloud;
  late _Phone ann;
  late _Phone bo;

  setUp(() async {
    cloud = _Cloud();
    final key = HouseholdKey.generate();
    final id = Household.randomHexId();
    ann = await _Phone.join(
      cloud,
      key,
      householdId: id,
      memberId: 'aaaaaaaaaaaaaaaa',
      name: 'Ann',
    );
    bo = await _Phone.join(
      cloud,
      key,
      householdId: id,
      memberId: 'bbbbbbbbbbbbbbbb',
      name: 'Bo',
      profile: const MemberProfile(
        slots: [MemberSlot(id: 'lunch', baseType: IntakeTypeEntity.lunch)],
        budgets: {'lunch': MacroPoints(carbs: 4, protein: 3, fat: 2)},
        diet: DietProfile(diet: DietStyle.vegetarian),
      ),
    );
    await bo.planner.saveDay(
      dayPlan(day, {
        'lunch': [plannedItem('Lentils', 200)],
      }),
    );
    await bo.sync.syncNow(now: day);
    await ann.sync.syncNow(now: day);
  });

  MenuEdit edit(List<String> foods) => MenuEdit(
    id: 'e-${foods.join()}',
    memberId: 'bbbbbbbbbbbbbbbb',
    date: day,
    slotId: 'lunch',
    items: [for (final f in foods) plannedItem(f, 150)],
    by: 'Ann',
    at: day,
  );

  test('a member sees the other\'s profile and that they allow changes', () {
    final other = ann.store.otherMembers().single;
    expect(other.name, 'Bo');
    expect(other.allowsEdits, isTrue);
    expect(other.profile!.budgets['lunch']!.total, 9);
    expect(other.profile!.diet!.diet, DietStyle.vegetarian);
  });

  test('a change to another member\'s menu reaches their menu', () async {
    await ann.store.editMemberMenu(edit(['Tofu', 'Rice']));
    // Shown on Ann's phone at once.
    expect(
      ann.store
          .otherMembers()
          .single
          .dayFor(day)!
          .itemsFor('lunch')
          .map((i) => i.name),
      ['Tofu', 'Rice'],
    );

    await ann.sync.syncNow(now: day);
    await bo.sync.syncNow(now: day);
    expect(bo.planner.getDay(day).itemsFor('lunch').map((i) => i.name), [
      'Tofu',
      'Rice',
    ]);

    // Ann's phone sees it confirmed and forgets it.
    await ann.sync.syncNow(now: day);
    expect(ann.store.pendingEdits(), isEmpty);
    expect(
      ann.store.otherMembers().single.dayFor(day)!.itemsFor('lunch'),
      hasLength(2),
    );
  });

  test('a member who turned it off keeps their menu', () async {
    await bo.store.setAllowEdits(false);
    await bo.sync.syncNow(now: day);
    await ann.sync.syncNow(now: day);
    expect(ann.store.otherMembers().single.allowsEdits, isFalse);
    expect(
      ann.store.otherMembers().single.profile!.diet,
      isNull,
      reason: 'nothing about their needs is shared either',
    );

    await ann.store.editMemberMenu(edit(['Steak']));
    await ann.sync.syncNow(now: day);
    await bo.sync.syncNow(now: day);
    expect(bo.planner.getDay(day).itemsFor('lunch').map((i) => i.name), [
      'Lentils',
    ]);
    // Handled (refused) all the same, so Ann's phone stops sending it.
    await ann.sync.syncNow(now: day);
    expect(ann.store.pendingEdits(), isEmpty);
  });

  test('a logged meal is not changed by someone else', () async {
    await bo.planner.saveDay(bo.planner.getDay(day).withLogged('lunch', true));
    await ann.store.editMemberMenu(edit(['Pizza']));
    await ann.sync.syncNow(now: day);
    await bo.sync.syncNow(now: day);
    expect(bo.planner.getDay(day).itemsFor('lunch').map((i) => i.name), [
      'Lentils',
    ]);
  });
}
