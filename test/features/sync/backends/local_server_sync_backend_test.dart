import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/sync/data/backends/local_server_sync_backend.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';

LocalServerSyncBackend _make(
  MockClient c, {
  String url = 'https://home.example.com:8443',
}) => LocalServerSyncBackend(
  c,
  baseUrl: Uri.parse(url),
  token: 'tok',
  householdId: 'hh',
);

void main() {
  test('testConnection hits /health with bearer token', () async {
    late http.Request seen;
    await _make(
      MockClient((r) async {
        seen = r;
        return http.Response('{"ok":true}', 200);
      }),
    ).testConnection();
    expect(seen.method, 'GET');
    expect(seen.url.toString(), 'https://home.example.com:8443/health');
    expect(seen.headers['Authorization'], 'Bearer tok');
  });

  test('testConnection rejects non-EatPoint answers', () async {
    await expectLater(
      _make(
        MockClient((r) async => http.Response('<html>', 200)),
      ).testConnection(),
      throwsA(isA<SyncBackendException>()),
    );
  });

  test('list, get, put', () async {
    final seen = <http.Request>[];
    final b = _make(
      MockClient((r) async {
        seen.add(r);
        if (r.method == 'PUT') return http.Response('', 204);
        if (r.url.path.endsWith('/blobs')) {
          return http.Response('{"names":["a.enc","b.enc"]}', 200);
        }
        return r.url.path.endsWith('gone.enc')
            ? http.Response('', 404)
            : http.Response.bytes([5, 6], 200);
      }),
    );
    expect(await b.list(), ['a.enc', 'b.enc']);
    expect(seen.last.url.path, '/h/hh/blobs');
    expect(await b.get('a.enc'), [5, 6]);
    expect(seen.last.url.path, '/h/hh/blobs/a.enc');
    expect(await b.get('gone.enc'), isNull);
    await b.put('a.enc', Uint8List.fromList([1]));
    expect(seen.last.method, 'PUT');
    expect(seen.last.url.path, '/h/hh/blobs/a.enc');
    expect(seen.last.bodyBytes, [1]);
    expect(seen.last.headers['Authorization'], 'Bearer tok');
  });

  test('error mapping', () async {
    await expectLater(
      _make(MockClient((r) async => http.Response('', 401))).list(),
      throwsA(
        isA<SyncBackendException>().having((e) => e.authFailed, 'a', true),
      ),
    );
    for (final e in <Object>[
      http.ClientException('x'),
      const SocketException('x'),
      TimeoutException('x'),
    ]) {
      await expectLater(
        _make(MockClient((r) async => throw e)).list(),
        throwsA(
          isA<SyncBackendException>().having((e) => e.authFailed, 'a', false),
        ),
      );
    }
    await expectLater(
      _make(MockClient((r) async => http.Response('', 500))).list(),
      throwsA(isA<SyncBackendException>()),
    );
  });

  test('name validation', () async {
    final b = _make(MockClient((r) async => http.Response('', 204)));
    await expectLater(b.get('../x'), throwsArgumentError);
    await expectLater(b.put('a/b', Uint8List(0)), throwsArgumentError);
  });

  test('http LAN rule', () async {
    final ok = MockClient((r) async => http.Response('{"ok":true}', 200));
    await _make(ok, url: 'http://192.168.1.20:8787').testConnection();
    await expectLater(
      _make(ok, url: 'http://example.com').testConnection(),
      throwsA(isA<SyncBackendException>()),
    );
  });
}
