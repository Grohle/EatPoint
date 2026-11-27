import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_crypto.dart';
import 'package:opennutritracker/features/sync/domain/household_sync_service.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:opennutritracker/features/sync/presentation/backend_setup_screen.dart';
import 'package:opennutritracker/features/sync/presentation/household_screen.dart';
import 'package:opennutritracker/features/sync/presentation/join_household_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../helpers/fake_hive_db_provider.dart';
import '../../points/points_test_support.dart';

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
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncService extends Fake implements HouseholdSyncService {
  int calls = 0;

  @override
  Future<HouseholdSyncResult?> syncNow({DateTime? now}) async {
    calls++;
    return const HouseholdSyncResult(membersSeen: 2, listChanged: false);
  }
}

class _Box extends MemoryStringBox {
  @override
  Iterable<dynamic> get keys => data.keys;

  @override
  Future<int> deleteAll(Iterable<dynamic> keys) async {
    keys.toList().forEach(data.remove);
    return 0;
  }
}

late _Box _box;
late _MemoryStorage _secure;
late HouseholdStore _store;
late _FakeSyncService _sync;

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: home,
);

Future<void> _enter(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
}

HouseholdInvite _invite() => HouseholdInvite(
  householdId: Household.randomHexId(),
  key: HouseholdKey.generate(),
  backend: const SyncBackendConfig(
    kind: SyncBackendKind.webdav,
    url: 'https://cloud.example/dav/eatpoint',
    user: 'ann',
  ),
  backendSecret: 'pw',
);

void main() {
  setUp(() async {
    await locator.reset();
    _box = _Box();
    _secure = _MemoryStorage();
    _store = HouseholdStore(
      FakeHiveDBProvider(pointsSettingsBox: _box),
      _secure,
    );
    _sync = _FakeSyncService();
    locator.registerSingleton<HouseholdStore>(_store);
    locator.registerSingleton<HouseholdSyncService>(_sync);
  });

  tearDown(() => locator.reset());

  testWidgets('not set up shows name field, create and join', (tester) async {
    await tester.pumpWidget(_app(const HouseholdScreen()));
    final s = _s(tester);
    expect(find.text(s.householdIntro), findsOneWidget);
    expect(find.text(s.householdCreate), findsOneWidget);
    expect(find.text(s.householdJoin), findsOneWidget);

    // Name is required.
    await tester.tap(find.text(s.householdCreate));
    await tester.pumpAndSettle();
    expect(find.byType(BackendSetupScreen), findsNothing);

    await tester.enterText(find.byType(TextFormField), 'Ann');
    await tester.tap(find.text(s.householdCreate));
    await tester.pumpAndSettle();
    expect(find.byType(BackendSetupScreen), findsOneWidget);
  });

  testWidgets('WebDAV setup creates the household and stores key + secret', (
    tester,
  ) async {
    final client = MockClient((request) async {
      expect(request.method, 'PROPFIND');
      return http.Response('<multistatus/>', 207);
    });
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    BackendSetupScreen(memberName: 'Ann', client: client),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final s = _s(tester);

    await tester.tap(find.text(s.householdStorageWebdav));
    await tester.pumpAndSettle();
    await _enter(tester, s.householdWebdavUrl, 'https://cloud.example/dav/ep');
    await _enter(tester, s.householdWebdavUser, 'ann');
    await _enter(tester, s.householdPassword, 'secret');
    await tester.scrollUntilVisible(
      find.text(s.householdTestAndCreate),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(s.householdTestAndCreate));
    await tester.pumpAndSettle();

    final household = _store.getHousehold();
    expect(household, isNotNull);
    expect(household!.memberName, 'Ann');
    expect(household.backend.kind, SyncBackendKind.webdav);
    expect(household.backend.user, 'ann');
    expect(await _store.readKey(), isNotNull);
    expect(await _store.readBackendSecret(), 'secret');
    expect(_sync.calls, 1);
    expect(find.byType(BackendSetupScreen), findsNothing);
  });

  testWidgets('a 401 shows the wrong-credentials message', (tester) async {
    final client = MockClient((_) async => http.Response('', 401));
    await tester.pumpWidget(
      _app(BackendSetupScreen(memberName: 'Ann', client: client)),
    );
    final s = _s(tester);
    await tester.tap(find.text(s.householdStorageWebdav));
    await tester.pumpAndSettle();
    await _enter(tester, s.householdWebdavUrl, 'https://cloud.example/dav/ep');
    await _enter(tester, s.householdWebdavUser, 'ann');
    await _enter(tester, s.householdPassword, 'bad');
    await tester.scrollUntilVisible(
      find.text(s.householdTestAndCreate),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(s.householdTestAndCreate));
    await tester.pumpAndSettle();

    expect(
      find.text(s.householdConnectionFailed(s.householdWrongCredentials)),
      findsOneWidget,
    );
    expect(_store.getHousehold(), isNull);
  });

  testWidgets('pasting a valid invite joins that household', (tester) async {
    final invite = _invite();
    await tester.pumpWidget(
      _app(JoinHouseholdScreen(memberName: 'Bo', showScanner: false)),
    );
    final s = _s(tester);
    await tester.tap(find.text(_m(tester).pasteButtonLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), invite.encode());
    await tester.tap(find.text(_m(tester).okButtonLabel));
    await tester.pumpAndSettle();

    final household = _store.getHousehold();
    expect(household?.householdId, invite.householdId);
    expect(household?.memberName, 'Bo');
    expect(await _store.readBackendSecret(), 'pw');
    expect((await _store.readKey())?.toBase64(), invite.key.toBase64());
    expect(_sync.calls, 1);
    expect(find.text(s.householdInvalidInvite), findsNothing);
  });

  testWidgets('pasting garbage shows the invalid-invite message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(JoinHouseholdScreen(memberName: 'Bo', showScanner: false)),
    );
    await tester.tap(find.text(_m(tester).pasteButtonLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.text(_m(tester).okButtonLabel));
    await tester.pumpAndSettle();
    expect(find.text(_s(tester).householdInvalidInvite), findsOneWidget);
    expect(_store.getHousehold(), isNull);
  });

  testWidgets('set-up state lists members, syncs and leaves', (tester) async {
    await _store.writeKey(HouseholdKey.generate());
    await _store.saveHousehold(
      Household(
        householdId: Household.randomHexId(),
        memberId: Household.randomHexId(8),
        memberName: 'Ann',
        backend: const SyncBackendConfig(
          kind: SyncBackendKind.supabase,
          url: 'https://abc.supabase.co',
        ),
        members: {'aabbccdd11223344': 'Bo'},
      ),
    );
    await tester.pumpWidget(_app(const HouseholdScreen()));
    final s = _s(tester);
    expect(find.text(s.householdYou('Ann')), findsOneWidget);
    expect(find.text('Bo'), findsOneWidget);
    expect(find.text(s.householdNeverSynced), findsOneWidget);
    expect(
      find.text(s.householdStorageInUse(s.householdStorageSupabase)),
      findsOneWidget,
    );

    await tester.tap(find.text(s.householdSyncNow));
    await tester.pumpAndSettle();
    expect(_sync.calls, 1);
    expect(find.text(s.householdSynced('2')), findsOneWidget);

    await tester.tap(find.text(s.householdLeave));
    await tester.pumpAndSettle();
    expect(find.text(s.householdLeaveConfirm), findsOneWidget);
    await tester.tap(find.text(s.householdLeave).last);
    await tester.pumpAndSettle();
    expect(_store.getHousehold(), isNull);
    expect(find.text(s.householdCreate), findsOneWidget);
  });
}

S _s(WidgetTester tester) => S.of(tester.element(find.byType(Scaffold).first));

MaterialLocalizations _m(WidgetTester tester) =>
    MaterialLocalizations.of(tester.element(find.byType(Scaffold).first));
