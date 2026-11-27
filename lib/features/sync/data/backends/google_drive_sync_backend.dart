import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../domain/sync_backend.dart';

/// Google sign-in for Drive sync.
///
/// Android needs an OAuth client registered for the app (package name and
/// signing certificate) and the *web* client ID of the same Google Cloud
/// project as [webClientId]; see docs/google-drive.md.
class GoogleDriveAuth {
  GoogleDriveAuth._();

  /// Full Drive access: a household folder is shared between two Google
  /// accounts, and `drive.file` would only show each account its own files.
  static const scope = 'https://www.googleapis.com/auth/drive';

  /// Built into release builds when the repository sets it; can also be
  /// typed in the household setup.
  static const builtInWebClientId = String.fromEnvironment(
    'EATPOINT_GOOGLE_WEB_CLIENT_ID',
  );

  static String? _initializedFor;
  static GoogleSignInAccount? _account;

  static Future<void> _init(String webClientId) async {
    if (_initializedFor == webClientId) return;
    if (_initializedFor != null) {
      throw SyncBackendException(
        'Google sign-in is already set up with another client ID; '
        'restart the app.',
      );
    }
    await GoogleSignIn.instance.initialize(serverClientId: webClientId);
    _initializedFor = webClientId;
  }

  /// Signs in and grants Drive access, asking the user. Returns the email.
  static Future<String> signIn(String webClientId) async {
    await _init(webClientId);
    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [scope],
      );
      await account.authorizationClient.authorizeScopes(const [scope]);
      _account = account;
      return account.email;
    } on GoogleSignInException catch (e) {
      throw GoogleSignInFailure(e.code.name, e.description);
    }
  }

  /// A Drive access token without asking the user, or an auth failure
  /// telling them to sign in again.
  static Future<String> accessToken(String webClientId) async {
    await _init(webClientId);
    var account = _account;
    account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) {
      throw SyncBackendException('Not signed in to Google', authFailed: true);
    }
    _account = account;
    final authz = await account.authorizationClient.authorizationForScopes(
      const [scope],
    );
    if (authz == null) {
      throw SyncBackendException('Drive access not granted', authFailed: true);
    }
    return authz.accessToken;
  }

  /// Drops a token Drive refused, so the next request gets a fresh one.
  static Future<void> forget(String token) async {
    try {
      await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
        accessToken: token,
      );
    } catch (_) {}
  }
}

/// Google refused or could not finish the sign-in. Kept apart from a wrong
/// password so the setup screen can say what Google actually answered.
class GoogleSignInFailure extends SyncBackendException {
  /// A `GoogleSignInExceptionCode` name, e.g. `canceled`.
  final String code;

  /// Google's own text, if any (e.g. "[16] Account reauth failed.").
  final String? description;

  GoogleSignInFailure(this.code, this.description)
    : super('Google sign-in failed ($code): ${description ?? ''}');

  /// The user closed Google's window. On Android, a misconfigured OAuth
  /// client is also reported as `canceled`, with a description.
  bool get canceled => code == 'canceled';

  /// The app is not set up in Google Cloud as Google expects.
  bool get misconfigured =>
      code == 'clientConfigurationError' ||
      code == 'providerConfigurationError' ||
      (canceled && (description ?? '').trim().isNotEmpty);
}

/// Keeps a household's encrypted blobs as files in a Google Drive folder,
/// shared with the other member.
class GoogleDriveSyncBackend implements SyncBackend {
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';
  static const folderMime = 'application/vnd.google-apps.folder';

  final http.Client _client;
  final String folderId;
  final Future<String> Function() _token;
  final Future<void> Function(String token) _forget;

  /// File ids by name, filled by [list].
  final Map<String, String> _ids = {};

  GoogleDriveSyncBackend(
    this._client, {
    required this.folderId,
    required Future<String> Function() token,
    Future<void> Function(String token)? forget,
  }) : _token = token,
       _forget = forget ?? ((_) async {});

  @override
  SyncBackendKind get kind => SyncBackendKind.googleDrive;

  /// Sends a request with a token, once more with a fresh one on 401.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _token();
      final response = await request({'Authorization': 'Bearer $token'});
      if (response.statusCode == 401 && attempt == 0) {
        await _forget(token);
        continue;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw SyncBackendException(
          'Google Drive refused access (${response.statusCode})',
          authFailed: true,
        );
      }
      return response;
    }
    throw SyncBackendException('Google Drive refused access', authFailed: true);
  }

  static void _check(http.Response r, String what) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    throw SyncBackendException('$what: HTTP ${r.statusCode} ${r.body}');
  }

  @override
  Future<void> testConnection() async {
    final r = await _send(
      (h) => _client.get(
        Uri.parse(
          '$_api/files/$folderId?fields=id,trashed,capabilities(canAddChildren)'
          '&supportsAllDrives=true',
        ),
        headers: h,
      ),
    );
    _check(r, 'Folder');
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    final caps = json['capabilities'] as Map<String, dynamic>? ?? const {};
    if (json['trashed'] == true || caps['canAddChildren'] != true) {
      throw SyncBackendException('The household folder cannot be written');
    }
  }

  @override
  Future<List<String>> list() async {
    _ids.clear();
    String? page;
    do {
      final q = Uri.encodeQueryComponent(
        "'$folderId' in parents and trashed = false",
      );
      final r = await _send(
        (h) => _client.get(
          Uri.parse(
            '$_api/files?q=$q&fields=nextPageToken,files(id,name)'
            '&pageSize=1000&supportsAllDrives=true'
            '&includeItemsFromAllDrives=true'
            '${page == null ? '' : '&pageToken=$page'}',
          ),
          headers: h,
        ),
      );
      _check(r, 'List');
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      for (final f in json['files'] as List? ?? const []) {
        if (f is Map && f['name'] is String && f['id'] is String) {
          _ids[f['name'] as String] = f['id'] as String;
        }
      }
      page = json['nextPageToken'] as String?;
    } while (page != null);
    return _ids.keys.toList();
  }

  Future<String?> _idOf(String name) async {
    if (!_ids.containsKey(name)) await list();
    return _ids[name];
  }

  @override
  Future<Uint8List?> get(String name) async {
    final id = await _idOf(name);
    if (id == null) return null;
    final r = await _send(
      (h) => _client.get(
        Uri.parse('$_api/files/$id?alt=media&supportsAllDrives=true'),
        headers: h,
      ),
    );
    if (r.statusCode == 404) return null;
    _check(r, 'Download');
    return r.bodyBytes;
  }

  @override
  Future<void> put(String name, Uint8List bytes) async {
    final id = await _idOf(name);
    if (id != null) {
      final r = await _send(
        (h) => _client.patch(
          Uri.parse(
            '$_upload/files/$id?uploadType=media&supportsAllDrives=true',
          ),
          headers: {...h, 'Content-Type': 'application/octet-stream'},
          body: bytes,
        ),
      );
      _check(r, 'Upload');
      return;
    }
    const boundary = 'eatpoint-sync-boundary';
    final metadata = jsonEncode({
      'name': name,
      'parents': [folderId],
    });
    final body = <int>[
      ...utf8.encode(
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      ),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--'),
    ];
    final r = await _send(
      (h) => _client.post(
        Uri.parse(
          '$_upload/files?uploadType=multipart&fields=id&supportsAllDrives=true',
        ),
        headers: {
          ...h,
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body,
      ),
    );
    _check(r, 'Upload');
    final created = jsonDecode(r.body) as Map<String, dynamic>;
    if (created['id'] is String) _ids[name] = created['id'] as String;
  }

  /// Creates the household's folder in the signed-in account's Drive.
  static Future<String> createFolder(
    http.Client client,
    String token,
    String name,
  ) async {
    final r = await client.post(
      Uri.parse('$_api/files?fields=id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': name, 'mimeType': folderMime}),
    );
    _check(r, 'Create folder');
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as String;
  }

  /// Gives [email] write access to the folder; Google emails them.
  static Future<void> shareFolder(
    http.Client client,
    String token,
    String folderId,
    String email,
  ) async {
    final r = await client.post(
      Uri.parse('$_api/files/$folderId/permissions?sendNotificationEmail=true'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': 'user',
        'role': 'writer',
        'emailAddress': email,
      }),
    );
    _check(r, 'Share folder');
  }
}
