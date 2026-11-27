import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/sync_backend.dart';

const syncRequestTimeout = Duration(seconds: 20);

final _blobNameRe = RegExp(r'^[A-Za-z0-9._-]{1,120}$');

/// Throws [ArgumentError] unless [name] is a safe blob name.
void validateBlobName(String name) {
  if (!_blobNameRe.hasMatch(name)) {
    throw ArgumentError.value(name, 'name', 'Invalid blob name');
  }
}

/// True for hosts on the user's own network.
bool isPrivateLanHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.local') || h == '::1') return true;
  final m = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
  ).firstMatch(h);
  if (m == null) return false;
  final o = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
  if (o.any((v) => v > 255)) return false;
  return o[0] == 10 ||
      o[0] == 127 ||
      (o[0] == 172 && o[1] >= 16 && o[1] <= 31) ||
      (o[0] == 192 && o[1] == 168);
}

/// Allows https everywhere, http only on a private LAN address.
void requireSecureOrLan(Uri url) {
  if (url.scheme == 'https') return;
  if (url.scheme == 'http' && isPrivateLanHost(url.host)) return;
  throw SyncBackendException(
    url.scheme == 'http'
        ? 'Plain http:// is only allowed for servers on your own network '
              '(192.168.x.x, 10.x.x.x, 172.16-31.x.x, *.local, localhost). '
              'Use https:// for ${url.host}.'
        : 'Unsupported URL scheme "${url.scheme}". Use https://.',
  );
}

/// Sends [request], mapping transport failures to [SyncBackendException].
Future<http.Response> sendRequest(
  http.Client client,
  http.BaseRequest request,
) async {
  try {
    final streamed = await client.send(request).timeout(syncRequestTimeout);
    return await http.Response.fromStream(streamed).timeout(syncRequestTimeout);
  } on TimeoutException {
    throw SyncBackendException('The server did not answer in time.');
  } on SocketException catch (e) {
    throw SyncBackendException('Cannot reach the server: ${e.message}');
  } on http.ClientException catch (e) {
    throw SyncBackendException('Cannot reach the server: ${e.message}');
  }
}

/// Throws unless [r] has a status in [ok] (default any 2xx).
void checkStatus(http.Response r, {Set<int>? ok}) {
  final good = ok != null
      ? ok.contains(r.statusCode)
      : r.statusCode >= 200 && r.statusCode < 300;
  if (good) return;
  if (r.statusCode == 401 || r.statusCode == 403) {
    throw SyncBackendException(
      'Access denied (${r.statusCode}). Check your credentials.',
      authFailed: true,
    );
  }
  throw SyncBackendException('Server returned HTTP ${r.statusCode}.');
}
