import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/sync_backend.dart';
import 'backend_common.dart';

/// Stores blobs as files in `<folderUrl>/eatpoint-<householdId>/` on a
/// WebDAV server such as Nextcloud.
class WebDavSyncBackend implements SyncBackend {
  final http.Client _client;
  final Uri folderUrl;
  final String user;
  final String password;
  final String householdId;

  WebDavSyncBackend(
    this._client, {
    required this.folderUrl,
    required this.user,
    required this.password,
    required this.householdId,
  });

  @override
  SyncBackendKind get kind => SyncBackendKind.webdav;

  Map<String, String> get _auth => {
    'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$password'))}',
  };

  Uri _folder() {
    requireSecureOrLan(folderUrl);
    final segs = folderUrl.pathSegments.where((s) => s.isNotEmpty).toList();
    return folderUrl.replace(
      pathSegments: [...segs, 'eatpoint-$householdId', ''],
    );
  }

  Uri _blob(String name) {
    validateBlobName(name);
    final segs = _folder().pathSegments.where((s) => s.isNotEmpty).toList();
    return folderUrl.replace(pathSegments: [...segs, name]);
  }

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) {
    final req = http.Request(method, url)
      ..headers.addAll({..._auth, ...headers});
    if (body != null) req.bodyBytes = body;
    return sendRequest(_client, req);
  }

  @override
  Future<void> testConnection() async {
    final folder = _folder();
    final r = await _send('PROPFIND', folder, headers: {'Depth': '0'});
    if (r.statusCode == 404) {
      final mk = await _send('MKCOL', folder);
      checkStatus(mk);
      return;
    }
    checkStatus(r, ok: {200, 207});
  }

  @override
  Future<List<String>> list() async {
    final r = await _send('PROPFIND', _folder(), headers: {'Depth': '1'});
    if (r.statusCode == 404) return [];
    checkStatus(r, ok: {200, 207});
    final re = RegExp(
      r'<(?:[\w.-]+:)?href\b[^>]*>\s*([^<]*?)\s*</(?:[\w.-]+:)?href>',
      caseSensitive: false,
    );
    final names = <String>[];
    for (final m in re.allMatches(
      utf8.decode(r.bodyBytes, allowMalformed: true),
    )) {
      var href = m.group(1)!;
      if (href.endsWith('/')) continue; // the folder itself or a subfolder
      final q = href.indexOf('?');
      if (q >= 0) href = href.substring(0, q);
      final last = href.substring(href.lastIndexOf('/') + 1);
      String decoded;
      try {
        decoded = Uri.decodeComponent(last);
      } on FormatException {
        continue;
      }
      if (decoded.isNotEmpty) names.add(decoded);
    }
    return names;
  }

  @override
  Future<Uint8List?> get(String name) async {
    final r = await _send('GET', _blob(name));
    if (r.statusCode == 404) return null;
    checkStatus(r);
    return r.bodyBytes;
  }

  @override
  Future<void> put(String name, Uint8List bytes) async {
    final r = await _send(
      'PUT',
      _blob(name),
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    checkStatus(r);
  }
}
