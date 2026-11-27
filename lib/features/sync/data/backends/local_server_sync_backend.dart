import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/sync_backend.dart';
import 'backend_common.dart';

/// Talks to the EatPoint sync service running on the user's own server.
class LocalServerSyncBackend implements SyncBackend {
  final http.Client _client;
  final Uri baseUrl;
  final String token;
  final String householdId;

  LocalServerSyncBackend(
    this._client, {
    required this.baseUrl,
    required this.token,
    required this.householdId,
  });

  @override
  SyncBackendKind get kind => SyncBackendKind.localServer;

  Uri _uri(List<String> tail) {
    requireSecureOrLan(baseUrl);
    final segs = baseUrl.pathSegments.where((s) => s.isNotEmpty).toList();
    return baseUrl.replace(pathSegments: [...segs, ...tail]);
  }

  Uri _blobs() => _uri(['h', householdId, 'blobs']);

  Future<http.Response> _send(String method, Uri url, {List<int>? body}) {
    final req = http.Request(method, url)
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/octet-stream';
      req.bodyBytes = body;
    }
    return sendRequest(_client, req);
  }

  @override
  Future<void> testConnection() async {
    final r = await _send('GET', _uri(['health']));
    checkStatus(r, ok: {200});
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map && j['ok'] == true) return;
    } on FormatException {
      // fall through
    }
    throw SyncBackendException('That address is not an EatPoint sync server.');
  }

  @override
  Future<List<String>> list() async {
    final r = await _send('GET', _blobs());
    checkStatus(r, ok: {200});
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map && j['names'] is List) {
        return (j['names'] as List).cast<String>();
      }
    } on FormatException {
      // fall through
    } on TypeError {
      // fall through
    }
    throw SyncBackendException('Unexpected answer from the sync server.');
  }

  @override
  Future<Uint8List?> get(String name) async {
    validateBlobName(name);
    final r = await _send('GET', _uri(['h', householdId, 'blobs', name]));
    if (r.statusCode == 404) return null;
    checkStatus(r);
    return r.bodyBytes;
  }

  @override
  Future<void> put(String name, Uint8List bytes) async {
    validateBlobName(name);
    final r = await _send(
      'PUT',
      _uri(['h', householdId, 'blobs', name]),
      body: bytes,
    );
    checkStatus(r);
  }
}
