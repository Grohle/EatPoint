import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/sync/data/backends/google_drive_sync_backend.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';

/// A tiny Drive: one folder, files by id, and the requests it saw.
class _FakeDrive {
  final files = <String, ({String name, List<int> bytes})>{};
  final requests = <http.Request>[];
  var nextId = 1;
  var rejectNextToken = false;
  var tokens = 0;

  MockClient client() => MockClient((request) async {
    requests.add(request);
    if (rejectNextToken) {
      rejectNextToken = false;
      return http.Response('', 401);
    }
    final path = request.url.path;
    if (path == '/drive/v3/files/folder1') {
      return http.Response(
        jsonEncode({
          'id': 'folder1',
          'trashed': false,
          'capabilities': {'canAddChildren': true},
        }),
        200,
      );
    }
    if (path == '/drive/v3/files' && request.method == 'GET') {
      expect(
        request.url.queryParameters['q'],
        contains("'folder1' in parents"),
      );
      return http.Response(
        jsonEncode({
          'files': [
            for (final e in files.entries) {'id': e.key, 'name': e.value.name},
          ],
        }),
        200,
      );
    }
    if (path.startsWith('/drive/v3/files/') && request.method == 'GET') {
      final id = path.split('/').last;
      final f = files[id];
      return f == null
          ? http.Response('', 404)
          : http.Response.bytes(f.bytes, 200);
    }
    if (path == '/upload/drive/v3/files' && request.method == 'POST') {
      // multipart/related: metadata JSON, then the bytes.
      final body = request.bodyBytes;
      final text = latin1.decode(body);
      final name = RegExp(r'"name":"([^"]+)"').firstMatch(text)!.group(1)!;
      expect(text, contains('"parents":["folder1"]'));
      final start = text.indexOf('application/octet-stream\r\n\r\n') + 28;
      final end = text.lastIndexOf('\r\n--eatpoint-sync-boundary--');
      final id = 'f${nextId++}';
      files[id] = (name: name, bytes: body.sublist(start, end));
      return http.Response(jsonEncode({'id': id}), 200);
    }
    if (path.startsWith('/upload/drive/v3/files/') &&
        request.method == 'PATCH') {
      final id = path.split('/').last;
      files[id] = (name: files[id]!.name, bytes: request.bodyBytes);
      return http.Response('{}', 200);
    }
    return http.Response('unexpected ${request.method} $path', 500);
  });

  GoogleDriveSyncBackend backend() => GoogleDriveSyncBackend(
    client(),
    folderId: 'folder1',
    token: () async => 'token-${++tokens}',
  );
}

void main() {
  test('stores, lists and reads encrypted blobs in the folder', () async {
    final drive = _FakeDrive();
    final backend = drive.backend();
    await backend.testConnection();
    expect(await backend.list(), isEmpty);

    await backend.put('member-a.json.enc', Uint8List.fromList([1, 2, 3, 250]));
    expect(await backend.list(), ['member-a.json.enc']);
    expect(await backend.get('member-a.json.enc'), [1, 2, 3, 250]);

    // Writing it again replaces the same file instead of adding one.
    await backend.put('member-a.json.enc', Uint8List.fromList([9]));
    expect(drive.files, hasLength(1));
    expect(await backend.get('member-a.json.enc'), [9]);
    expect(await backend.get('missing.json.enc'), isNull);
    expect(
      drive.requests.every(
        (r) => r.headers['Authorization']?.startsWith('Bearer token-') ?? false,
      ),
      isTrue,
    );
  });

  test('a refused token is replaced once', () async {
    final drive = _FakeDrive()..rejectNextToken = true;
    final forgotten = <String>[];
    final backend = GoogleDriveSyncBackend(
      drive.client(),
      folderId: 'folder1',
      token: () async => 'token-${++drive.tokens}',
      forget: (t) async => forgotten.add(t),
    );
    await backend.testConnection();
    expect(forgotten, ['token-1']);
    expect(drive.requests.last.headers['Authorization'], 'Bearer token-2');
  });

  test('no access at all is an auth failure', () async {
    final backend = GoogleDriveSyncBackend(
      MockClient((_) async => http.Response('', 401)),
      folderId: 'folder1',
      token: () async => 't',
    );
    expect(
      backend.list,
      throwsA(
        isA<SyncBackendException>().having((e) => e.authFailed, 'auth', true),
      ),
    );
  });

  test('the config keeps the folder and the client ID for the invite', () {
    const config = SyncBackendConfig(
      kind: SyncBackendKind.googleDrive,
      url: 'folder1',
      user: '123-abc.apps.googleusercontent.com',
    );
    final back = SyncBackendConfig.fromJson(config.toJson())!;
    expect(back.kind, SyncBackendKind.googleDrive);
    expect(back.url, 'folder1');
    expect(back.user, '123-abc.apps.googleusercontent.com');
  });
}
