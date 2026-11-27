import 'dart:typed_data';

/// Where a household's encrypted data is kept.
enum SyncBackendKind {
  /// A Supabase project the user owns. Recommended: realtime-friendly and
  /// free for a household's volume.
  supabase,

  /// A Nextcloud or other WebDAV server.
  webdav,

  /// A server the user runs (e.g. Ubuntu Server) that the app set up over
  /// SSH with the EatPoint sync service.
  localServer,

  /// Google Drive. Not available yet (needs an OAuth client).
  googleDrive,
}

/// Raised by a backend. [authFailed] separates a wrong password or token
/// from a network problem so the UI can say which.
class SyncBackendException implements Exception {
  final String message;
  final bool authFailed;

  SyncBackendException(this.message, {this.authFailed = false});

  @override
  String toString() => 'SyncBackendException($message)';
}

/// A key-value blob store scoped to one household. Every blob is already
/// encrypted by the caller; backends never see plaintext.
///
/// Names are short ASCII strings such as `member-3f2a.json.enc`.
abstract class SyncBackend {
  SyncBackendKind get kind;

  /// Checks that the store is reachable and the credentials work.
  Future<void> testConnection();

  /// Every blob name in this household's space.
  Future<List<String>> list();

  /// The blob, or null when it does not exist.
  Future<Uint8List?> get(String name);

  /// Creates or replaces a blob.
  Future<void> put(String name, Uint8List bytes);
}

/// Non-secret settings of a backend. Secrets (passwords, tokens, keys) are
/// kept in the platform keystore under [secretKey] and passed separately.
class SyncBackendConfig {
  final SyncBackendKind kind;

  /// Supabase project URL, WebDAV folder URL or local server base URL.
  final String url;

  /// WebDAV user name; unused by the other backends.
  final String? user;

  const SyncBackendConfig({required this.kind, required this.url, this.user});

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'url': url,
    if (user != null) 'user': user,
  };

  static SyncBackendConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = SyncBackendKind.values.where((k) => k.name == json['kind']);
    final url = json['url'];
    if (kind.isEmpty || url is! String) return null;
    return SyncBackendConfig(
      kind: kind.first,
      url: url,
      user: json['user'] as String?,
    );
  }
}
