import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

Future<bool> _hasPython() async {
  try {
    final r = await Process.run('python3', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

void main() {
  final hasPython = Process.runSync('which', ['python3']).exitCode == 0;
  const token = 'secret-token-123';
  final household = 'a' * 32;

  group('eatpoint_sync_server.py', () {
    late Process proc;
    late Directory tmp;
    late int port;
    late HttpClient client;

    Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

    Future<HttpClientResponse> send(
      String method,
      String path, {
      String? auth = token,
      List<int>? body,
    }) async {
      final req = await client.openUrl(method, url(path));
      if (auth != null) req.headers.set('Authorization', 'Bearer $auth');
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      return req.close();
    }

    Future<List<int>> bytes(HttpClientResponse r) =>
        r.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

    setUpAll(() async {
      if (!hasPython || !await _hasPython()) return;
      tmp = await Directory.systemTemp.createTemp('eatpoint_srv');
      File('${tmp.path}/token').writeAsStringSync('$token\n');
      port = await _freePort();
      proc = await Process.start('python3', [
        'assets/server/eatpoint_sync_server.py',
        '--db',
        '${tmp.path}/sync.db',
        '--port',
        '$port',
        '--host',
        '127.0.0.1',
        '--token-file',
        '${tmp.path}/token',
      ]);
      proc.stdout.drain<void>();
      proc.stderr.drain<void>();
      client = HttpClient();
      // wait for readiness
      for (var i = 0; i < 50; i++) {
        try {
          final r = await send('GET', '/health', auth: null);
          await bytes(r);
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    tearDownAll(() async {
      if (!hasPython) return;
      client.close(force: true);
      proc.kill();
      await proc.exitCode;
      await tmp.delete(recursive: true);
    });

    test('health needs no auth', () async {
      final r = await send('GET', '/health', auth: null);
      expect(r.statusCode, 200);
      final j = jsonDecode(utf8.decode(await bytes(r)));
      expect(j, {'ok': true, 'version': '1'});
    });

    test('401 without or with wrong token', () async {
      var r = await send('GET', '/h/$household/blobs', auth: null);
      await bytes(r);
      expect(r.statusCode, 401);
      r = await send('GET', '/h/$household/blobs', auth: 'nope');
      await bytes(r);
      expect(r.statusCode, 401);
    });

    test('list empty, put/get round trip, list, 404', () async {
      var r = await send('GET', '/h/$household/blobs');
      expect(r.statusCode, 200);
      expect(jsonDecode(utf8.decode(await bytes(r))), {'names': []});

      r = await send('GET', '/h/$household/blobs/missing.bin');
      await bytes(r);
      expect(r.statusCode, 404);

      final rnd = Random(1);
      final data = Uint8List.fromList(
        List.generate(10000, (_) => rnd.nextInt(256)),
      );
      r = await send('PUT', '/h/$household/blobs/day-1.bin', body: data);
      await bytes(r);
      expect(r.statusCode, 204);

      r = await send('GET', '/h/$household/blobs/day-1.bin');
      expect(r.statusCode, 200);
      expect(r.headers.contentType?.mimeType, 'application/octet-stream');
      expect(await bytes(r), data);

      r = await send('GET', '/h/$household/blobs');
      expect(jsonDecode(utf8.decode(await bytes(r))), {
        'names': ['day-1.bin'],
      });
    });

    test('invalid household or name gives 400', () async {
      var r = await send('GET', '/h/XYZ/blobs');
      await bytes(r);
      expect(r.statusCode, 400);
      r = await send('GET', '/h/$household/blobs/bad%20name');
      await bytes(r);
      expect(r.statusCode, 400);
      r = await send('PUT', '/h/$household/blobs/bad%20name', body: [1]);
      await bytes(r);
      expect(r.statusCode, 400);
    });

    test('unknown routes give 404', () async {
      final r = await send('GET', '/nothing');
      await bytes(r);
      expect(r.statusCode, 404);
    });

    test('body over 5 MB gives 413', () async {
      final big = Uint8List(5 * 1024 * 1024 + 1);
      final r = await send('PUT', '/h/$household/blobs/big.bin', body: big);
      await bytes(r);
      expect(r.statusCode, 413);
    });
  }, skip: hasPython ? false : 'python3 not available');
}
