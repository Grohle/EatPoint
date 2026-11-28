import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/features/backup/data/backup_service.dart';
import 'package:opennutritracker/features/backup/data/backup_settings.dart';
import 'package:opennutritracker/features/sync/data/backends/google_drive_sync_backend.dart';

/// Backups in an "EatPoint backups" folder of the user's Google Drive.
class DriveBackup {
  static const folderName = 'EatPoint backups';

  final http.Client _client;
  final BackupSettings _settings;

  /// The Google Cloud web client ID to sign in with.
  final String clientId;

  DriveBackup(this._client, this._settings, {required this.clientId});

  Future<GoogleDriveSyncBackend> _backend({bool create = true}) async {
    var folder = _settings.driveFolder;
    if (folder == null) {
      if (!create) throw StateError('No backup folder yet');
      final token = await GoogleDriveAuth.accessToken(clientId);
      folder = await GoogleDriveSyncBackend.createFolder(
        _client,
        token,
        folderName,
      );
      await _settings.setDriveFolder(folder);
    }
    return GoogleDriveSyncBackend(
      _client,
      folderId: folder,
      token: () => GoogleDriveAuth.accessToken(clientId),
      forget: GoogleDriveAuth.forget,
    );
  }

  /// Uploads [bytes] as a new backup and keeps only the latest few.
  Future<void> upload(Uint8List bytes, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final backend = await _backend();
    await backend.put(BackupService.fileName(at), bytes);
    final names =
        (await backend.list()).where(BackupService.isBackupName).toList()
          ..sort();
    for (final old in names.take(
      (names.length - BackupSettings.keep).clamp(0, names.length),
    )) {
      await backend.delete(old);
    }
    await _settings.setLastAt(at);
  }

  /// The backups in Drive, newest first.
  Future<List<String>> list() async {
    if (_settings.driveFolder == null) return const [];
    final names =
        (await (await _backend(
            create: false,
          )).list()).where(BackupService.isBackupName).toList()
          ..sort((a, b) => b.compareTo(a));
    return names;
  }

  Future<Uint8List?> download(String name) async =>
      (await _backend(create: false)).get(name);
}
