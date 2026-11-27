import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:opennutritracker/features/sync/data/backends/google_drive_sync_backend.dart';
import 'package:opennutritracker/features/sync/data/backends/local_server_sync_backend.dart';
import 'package:opennutritracker/features/sync/data/backends/supabase_sync_backend.dart';
import 'package:opennutritracker/features/sync/data/backends/sync_backend_factory.dart';
import 'package:opennutritracker/features/sync/data/backends/webdav_sync_backend.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';

void main() {
  final client = MockClient((r) async => throw UnimplementedError());
  SyncBackend make(SyncBackendKind k) => createSyncBackend(
    client,
    SyncBackendConfig(kind: k, url: 'https://x.example.com', user: 'u'),
    householdId: 'h',
    secret: 's',
  );

  test('maps kinds to backends', () {
    expect(make(SyncBackendKind.webdav), isA<WebDavSyncBackend>());
    expect(make(SyncBackendKind.supabase), isA<SupabaseSyncBackend>());
    expect(make(SyncBackendKind.localServer), isA<LocalServerSyncBackend>());
  });

  test('google drive maps to the Drive backend', () {
    expect(make(SyncBackendKind.googleDrive), isA<GoogleDriveSyncBackend>());
  });
}
