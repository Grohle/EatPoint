import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/sync/data/backends/supabase_sync_backend.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';

SupabaseSyncBackend _make(MockClient c) => SupabaseSyncBackend(
  c,
  projectUrl: Uri.parse('https://abcd.supabase.co'),
  anonKey: 'anon',
  householdId: 'a' * 32,
);

void main() {
  test('list posts to rpc with headers', () async {
    late http.Request seen;
    final names = await _make(
      MockClient((r) async {
        seen = r;
        return http.Response('["a.enc","b.enc"]', 200);
      }),
    ).list();
    expect(names, ['a.enc', 'b.enc']);
    expect(seen.method, 'POST');
    expect(
      seen.url.toString(),
      'https://abcd.supabase.co/rest/v1/rpc/eatpoint_list',
    );
    expect(seen.headers['apikey'], 'anon');
    expect(seen.headers['Authorization'], 'Bearer anon');
    expect(seen.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(seen.body), {'p_household': 'a' * 32});
  });

  test('get decodes base64 and maps null', () async {
    late http.Request seen;
    final b = _make(
      MockClient((r) async {
        seen = r;
        return http.Response(
          r.body.contains('gone')
              ? 'null'
              : jsonEncode(base64Encode([1, 2, 3])),
          200,
        );
      }),
    );
    expect(await b.get('a.enc'), [1, 2, 3]);
    expect(seen.url.path, '/rest/v1/rpc/eatpoint_get');
    expect(jsonDecode(seen.body), {'p_household': 'a' * 32, 'p_name': 'a.enc'});
    expect(await b.get('gone.enc'), isNull);
  });

  test('put sends base64', () async {
    late http.Request seen;
    await _make(
      MockClient((r) async {
        seen = r;
        return http.Response('', 204);
      }),
    ).put('a.enc', Uint8List.fromList([7, 8]));
    expect(seen.url.path, '/rest/v1/rpc/eatpoint_put');
    expect(jsonDecode(seen.body), {
      'p_household': 'a' * 32,
      'p_name': 'a.enc',
      'p_data': base64Encode([7, 8]),
    });
  });

  test('testConnection is list; errors map', () async {
    var calls = 0;
    await _make(
      MockClient((r) async {
        calls++;
        expect(r.url.path, endsWith('eatpoint_list'));
        return http.Response('[]', 200);
      }),
    ).testConnection();
    expect(calls, 1);
    for (final code in [401, 403]) {
      await expectLater(
        _make(MockClient((r) async => http.Response('', code))).list(),
        throwsA(
          isA<SyncBackendException>().having((e) => e.authFailed, 'a', true),
        ),
      );
    }
    await expectLater(
      _make(MockClient((r) async => http.Response('', 404))).list(),
      throwsA(
        isA<SyncBackendException>().having((e) => e.authFailed, 'a', false),
      ),
    );
    for (final e in <Object>[
      http.ClientException('x'),
      const SocketException('x'),
      TimeoutException('x'),
    ]) {
      await expectLater(
        _make(MockClient((r) async => throw e)).list(),
        throwsA(isA<SyncBackendException>()),
      );
    }
  });

  test('name validation', () async {
    final b = _make(MockClient((r) async => http.Response('', 200)));
    await expectLater(b.get('a b'), throwsArgumentError);
    await expectLater(b.put('', Uint8List(0)), throwsArgumentError);
  });

  test('projectRefFromUrl', () {
    expect(
      SupabaseSyncBackend.projectRefFromUrl(
        Uri.parse('https://xyz123.supabase.co'),
      ),
      'xyz123',
    );
    expect(
      SupabaseSyncBackend.projectRefFromUrl(Uri.parse('https://example.com')),
      isNull,
    );
  });

  test('setupSql is locked down', () {
    final sql = SupabaseSyncBackend.setupSql.toLowerCase();
    expect(sql, contains('security definer'));
    expect(sql, contains('set search_path = public'));
    expect(sql, contains('enable row level security'));
    expect(sql, isNot(contains('create policy')));
    expect(sql, contains('{32,}'));
  });

  test('runSetupWithAccessToken posts query', () async {
    late http.Request seen;
    await SupabaseSyncBackend.runSetupWithAccessToken(
      MockClient((r) async {
        seen = r;
        return http.Response('[]', 201);
      }),
      projectRef: 'xyz',
      personalAccessToken: 'sbp_1',
    );
    expect(
      seen.url.toString(),
      'https://api.supabase.com/v1/projects/xyz/database/query',
    );
    expect(seen.headers['Authorization'], 'Bearer sbp_1');
    expect(jsonDecode(seen.body)['query'], SupabaseSyncBackend.setupSql);
    await expectLater(
      SupabaseSyncBackend.runSetupWithAccessToken(
        MockClient((r) async => http.Response('', 401)),
        projectRef: 'xyz',
        personalAccessToken: 'bad',
      ),
      throwsA(
        isA<SyncBackendException>().having((e) => e.authFailed, 'a', true),
      ),
    );
  });
}
