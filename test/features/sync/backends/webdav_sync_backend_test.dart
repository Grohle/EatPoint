import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/sync/data/backends/webdav_sync_backend.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';

const _multistatus = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns">
 <d:response>
  <d:href>/remote.php/dav/files/anna/EatPoint/eatpoint-abc/</d:href>
  <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
  <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
 </d:response>
 <d:response>
  <d:href>/remote.php/dav/files/anna/EatPoint/eatpoint-abc/member-3f2a.json.enc</d:href>
  <d:propstat><d:prop><d:getcontentlength>12</d:getcontentlength></d:prop>
  <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
 </d:response>
 <d:response>
  <d:href>/remote.php/dav/files/anna/EatPoint/eatpoint-abc/my%20file%2B1.enc</d:href>
  <d:propstat><d:prop/><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
 </d:response>
</d:multistatus>''';

WebDavSyncBackend _make(
  MockClient c, {
  String url = 'https://cloud.example.com/dav/EatPoint',
}) => WebDavSyncBackend(
  c,
  folderUrl: Uri.parse(url),
  user: 'anna',
  password: 'pw',
  householdId: 'abc',
);

void main() {
  final auth = 'Basic ${base64Encode(utf8.encode('anna:pw'))}';

  test('list sends PROPFIND depth 1 and parses Nextcloud response', () async {
    late http.Request seen;
    final b = _make(
      MockClient((r) async {
        seen = r;
        return http.Response(_multistatus, 207);
      }),
    );
    final names = await b.list();
    expect(seen.method, 'PROPFIND');
    expect(
      seen.url.toString(),
      'https://cloud.example.com/dav/EatPoint/eatpoint-abc/',
    );
    expect(seen.headers['Depth'], '1');
    expect(seen.headers['Authorization'], auth);
    expect(names, ['member-3f2a.json.enc', 'my file+1.enc']);
  });

  test('list parses uppercase D: prefix', () async {
    final b = _make(
      MockClient(
        (r) async => http.Response(
          '<D:multistatus xmlns:D="DAV:"><D:response><D:href>/x/eatpoint-abc/a.enc</D:href></D:response></D:multistatus>',
          207,
        ),
      ),
    );
    expect(await b.list(), ['a.enc']);
  });

  test('put and get', () async {
    final seen = <http.Request>[];
    final b = _make(
      MockClient((r) async {
        seen.add(r);
        if (r.method == 'GET') {
          return r.url.path.endsWith('missing.enc')
              ? http.Response('', 404)
              : http.Response.bytes([1, 2, 3], 200);
        }
        return http.Response('', 201);
      }),
    );
    await b.put('a.enc', Uint8List.fromList([9, 8]));
    expect(seen.first.method, 'PUT');
    expect(
      seen.first.url.toString(),
      'https://cloud.example.com/dav/EatPoint/eatpoint-abc/a.enc',
    );
    expect(seen.first.headers['Content-Type'], 'application/octet-stream');
    expect(seen.first.bodyBytes, [9, 8]);
    expect(await b.get('x.enc'), [1, 2, 3]);
    expect(await b.get('missing.enc'), isNull);
  });

  test('testConnection creates folder with MKCOL on 404', () async {
    final methods = <String>[];
    final b = _make(
      MockClient((r) async {
        methods.add(r.method);
        return http.Response('', r.method == 'PROPFIND' ? 404 : 201);
      }),
    );
    await b.testConnection();
    expect(methods, ['PROPFIND', 'MKCOL']);
  });

  test('testConnection ok when folder exists', () async {
    final methods = <String>[];
    final b = _make(
      MockClient((r) async {
        methods.add(r.method);
        expect(r.headers['Depth'], '0');
        return http.Response('', 207);
      }),
    );
    await b.testConnection();
    expect(methods, ['PROPFIND']);
  });

  test('401 and 403 map to authFailed', () async {
    for (final code in [401, 403]) {
      final b = _make(MockClient((r) async => http.Response('', code)));
      await expectLater(
        b.list(),
        throwsA(
          isA<SyncBackendException>().having(
            (e) => e.authFailed,
            'authFailed',
            true,
          ),
        ),
      );
    }
  });

  test(
    'other errors and network failures map to SyncBackendException',
    () async {
      final errors = <Object>[
        http.ClientException('x'),
        const SocketException('down'),
        TimeoutException('slow'),
      ];
      for (final e in errors) {
        final b = _make(MockClient((r) async => throw e));
        await expectLater(
          b.get('a.enc'),
          throwsA(
            isA<SyncBackendException>().having(
              (e) => e.authFailed,
              'authFailed',
              false,
            ),
          ),
        );
      }
      final b = _make(MockClient((r) async => http.Response('', 500)));
      await expectLater(
        b.put('a.enc', Uint8List(1)),
        throwsA(isA<SyncBackendException>()),
      );
    },
  );

  test('validates blob names', () async {
    final b = _make(MockClient((r) async => http.Response('', 200)));
    for (final bad in ['', '../x', 'a/b', 'a b', 'a' * 121]) {
      await expectLater(b.get(bad), throwsArgumentError);
      await expectLater(b.put(bad, Uint8List(0)), throwsArgumentError);
    }
  });

  test('http only allowed on LAN hosts', () async {
    final ok = MockClient((r) async => http.Response('', 207));
    for (final u in [
      'http://192.168.1.5/dav',
      'http://10.0.0.2/dav',
      'http://172.20.1.1/dav',
      'http://nas.local/dav',
      'http://localhost:8080/dav',
    ]) {
      await _make(ok, url: u).testConnection();
    }
    for (final u in [
      'http://example.com/dav',
      'http://172.32.0.1/dav',
      'http://8.8.8.8/dav',
    ]) {
      await expectLater(
        _make(ok, url: u).testConnection(),
        throwsA(isA<SyncBackendException>()),
      );
    }
  });
}
