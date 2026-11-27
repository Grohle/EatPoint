import 'package:http/http.dart' as http;

import '../../domain/sync_backend.dart';
import 'local_server_sync_backend.dart';
import 'supabase_sync_backend.dart';
import 'webdav_sync_backend.dart';

/// Builds the backend for [config]. [secret] is the WebDAV password,
/// Supabase anon key or local server token.
SyncBackend createSyncBackend(
  http.Client client,
  SyncBackendConfig config, {
  required String householdId,
  required String? secret,
}) {
  switch (config.kind) {
    case SyncBackendKind.webdav:
      return WebDavSyncBackend(
        client,
        folderUrl: Uri.parse(config.url),
        user: config.user ?? '',
        password: secret ?? '',
        householdId: householdId,
      );
    case SyncBackendKind.supabase:
      return SupabaseSyncBackend(
        client,
        projectUrl: Uri.parse(config.url),
        anonKey: secret ?? '',
        householdId: householdId,
      );
    case SyncBackendKind.localServer:
      return LocalServerSyncBackend(
        client,
        baseUrl: Uri.parse(config.url),
        token: secret ?? '',
        householdId: householdId,
      );
    case SyncBackendKind.googleDrive:
      throw UnsupportedError('Google Drive sync is in development');
  }
}
