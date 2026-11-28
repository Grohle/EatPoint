import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/backup/data/backup_service.dart';
import 'package:opennutritracker/features/backup/data/backup_settings.dart';
import 'package:opennutritracker/features/backup/data/drive_backup.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/sync/data/backends/google_drive_sync_backend.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:opennutritracker/features/sync/presentation/storage_labels.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// The Google Cloud web client ID for Drive backups: the one saved for
/// backups, else the household's (when it syncs through Drive), else the
/// one built into the app.
String? driveBackupClientId(BackupSettings settings) {
  final saved = settings.driveClientId;
  if (saved != null && saved.isNotEmpty) return saved;
  if (locator.isRegistered<HouseholdStore>()) {
    final backend = locator<HouseholdStore>().getHousehold()?.backend;
    if (backend?.kind == SyncBackendKind.googleDrive &&
        (backend?.user ?? '').isNotEmpty) {
      return backend!.user;
    }
  }
  final builtIn = GoogleDriveAuth.builtInWebClientId;
  return builtIn.isEmpty ? null : builtIn;
}

/// Copy everything to a file, any app (Drive, Dropbox, email…) or straight
/// to Google Drive, now or automatically; and put a copy back.
class BackupScreen extends StatefulWidget {
  final BackupService? service;
  final BackupSettings? settings;

  const BackupScreen({super.key, this.service, this.settings});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final BackupService _service =
      widget.service ?? locator<BackupService>();
  late final BackupSettings _settings =
      widget.settings ?? locator<BackupSettings>();
  final _client = http.Client();
  bool _busy = false;
  String? _email;
  List<String>? _driveBackups;

  @override
  void initState() {
    super.initState();
    _settings.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    _settings.revision.removeListener(_refresh);
    _client.close();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<String?> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await task();
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        final s = S.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? s.backupNotABackup
                  : s.backupFailed(syncFailureReason(s, e)),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _saveToPhone() async {
    final s = S.of(context);
    final bytes = await _service.build();
    final path = await FilePicker.saveFile(
      fileName: BackupService.fileName(DateTime.now()),
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: bytes,
    );
    return path == null ? null : s.backupSaved;
  }

  Future<String?> _sendTo() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final bytes = await _service.build();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${BackupService.fileName(DateTime.now())}');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        sharePositionOrigin: origin,
      ),
    );
    return null;
  }

  DriveBackup? _drive() {
    final id = driveBackupClientId(_settings);
    return id == null ? null : DriveBackup(_client, _settings, clientId: id);
  }

  Future<String?> _connectDrive() async {
    final s = S.of(context);
    var id = driveBackupClientId(_settings);
    if (id == null) {
      id = await _askClientId();
      if (id == null) return null;
      await _settings.setDriveClientId(id);
    }
    _email = await GoogleDriveAuth.signIn(id);
    await _loadDriveList();
    return s.householdDriveSignedIn(_email!);
  }

  Future<String?> _askClientId() async {
    final s = S.of(context);
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.householdDriveClientId),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(helperText: s.householdDriveClientIdHelp),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _loadDriveList() async {
    final drive = _drive();
    if (drive == null) return;
    final list = await drive.list();
    if (mounted) setState(() => _driveBackups = list);
  }

  Future<String?> _uploadToDrive() async {
    final s = S.of(context);
    final drive = _drive();
    if (drive == null) return _connectDrive();
    _email ??= await GoogleDriveAuth.signIn(drive.clientId);
    await drive.upload(await _service.build());
    await _loadDriveList();
    return s.backupUploaded;
  }

  Future<bool> _confirmRestore() async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.backupRestoreTitle),
        content: Text(s.backupRestoreBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.backupRestore),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<String?> _restoreBytes(Uint8List bytes) async {
    final s = S.of(context);
    await _service.restore(bytes);
    if (locator.isRegistered<PlannerDataSource>()) {
      locator<PlannerDataSource>().revision.value++;
    }
    if (locator.isRegistered<PointsSettingsDataSource>()) {
      locator<PointsSettingsDataSource>().revision.value++;
    }
    return s.backupRestored;
  }

  Future<String?> _restoreFromFile() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null || !mounted) return null;
    if (!await _confirmRestore()) return null;
    return _restoreBytes(await picked.readAsBytes());
  }

  Future<String?> _restoreFromDrive(String name) async {
    if (!await _confirmRestore()) return null;
    final drive = _drive();
    final bytes = await drive?.download(name);
    if (bytes == null) return null;
    return _restoreBytes(bytes);
  }

  String _when(DateTime? at) {
    if (at == null) return S.of(context).backupNever;
    final locale = Localizations.localeOf(context).toString();
    return '${DateFormat.yMMMd(locale).format(at)} '
        '${DateFormat.Hm(locale).format(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    Widget section(String text) => Padding(
      padding: const EdgeInsets.only(
        top: Dimens.spacing24,
        bottom: Dimens.spacing8,
      ),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    final hasDrive = driveBackupClientId(_settings) != null;
    return Scaffold(
      appBar: AppBar(title: Text(s.backupTitle)),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(Dimens.spacing16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            Text(s.backupIntro, style: theme.textTheme.bodyMedium),
            section(s.backupMakeTitle),
            Semantics(
              identifier: 'backup-save-phone',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.save_alt_rounded),
                title: Text(s.backupSavePhone),
                subtitle: Text(s.backupSavePhoneHint),
                onTap: () => _run(_saveToPhone),
              ),
            ),
            Semantics(
              identifier: 'backup-send-to',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.ios_share_rounded),
                title: Text(s.backupSendTo),
                subtitle: Text(s.backupSendToHint),
                onTap: () => _run(_sendTo),
              ),
            ),
            section(s.backupDriveTitle),
            Text(
              hasDrive ? s.backupDriveHint : s.backupDriveSetupHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Dimens.spacing8),
            Wrap(
              spacing: Dimens.spacing8,
              runSpacing: Dimens.spacing8,
              children: [
                Semantics(
                  identifier: 'backup-drive-upload',
                  child: FilledButton.icon(
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(s.backupDriveUpload),
                    onPressed: () => _run(_uploadToDrive),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.login_rounded),
                  label: Text(
                    _email == null
                        ? s.householdDriveSignIn
                        : s.householdDriveSignedIn(_email!),
                  ),
                  onPressed: () => _run(_connectDrive),
                ),
              ],
            ),
            const SizedBox(height: Dimens.spacing12),
            Text(s.backupAuto, style: theme.textTheme.titleSmall),
            const SizedBox(height: Dimens.spacing4),
            Semantics(
              identifier: 'backup-auto',
              child: SegmentedButton<AutoBackup>(
                segments: [
                  ButtonSegment(
                    value: AutoBackup.off,
                    label: Text(s.backupAutoOff),
                  ),
                  ButtonSegment(
                    value: AutoBackup.daily,
                    label: Text(s.backupAutoDaily),
                  ),
                  ButtonSegment(
                    value: AutoBackup.weekly,
                    label: Text(s.backupAutoWeekly),
                  ),
                ],
                selected: {_settings.auto},
                onSelectionChanged: (v) => _settings.setAuto(v.first),
              ),
            ),
            const SizedBox(height: Dimens.spacing4),
            Text(
              s.backupLast(_when(_settings.lastAt)),
              style: theme.textTheme.bodySmall,
            ),
            section(s.backupRestoreTitle),
            Semantics(
              identifier: 'backup-restore-file',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restore_rounded),
                title: Text(s.backupRestoreFile),
                subtitle: Text(s.backupRestoreFileHint),
                onTap: () => _run(_restoreFromFile),
              ),
            ),
            if (hasDrive)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_download_outlined),
                title: Text(s.backupRestoreDrive),
                trailing: const Icon(Icons.refresh_rounded),
                onTap: () => _run(() async {
                  _email ??= await GoogleDriveAuth.signIn(
                    driveBackupClientId(_settings)!,
                  );
                  await _loadDriveList();
                  return null;
                }),
              ),
            if (_driveBackups != null && _driveBackups!.isEmpty)
              Text(s.backupDriveNone, style: theme.textTheme.bodySmall),
            for (final name in _driveBackups ?? const <String>[])
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: Dimens.spacing32),
                title: Text(name),
                trailing: TextButton(
                  onPressed: () => _run(() => _restoreFromDrive(name)),
                  child: Text(s.backupRestore),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// On opening the app: an automatic copy to Google Drive when one is due.
/// Silent: when Google needs the user to sign in again, it waits.
Future<void> maybeAutoBackup() async {
  if (!locator.isRegistered<BackupSettings>()) return;
  final settings = locator<BackupSettings>();
  final now = DateTime.now();
  if (!settings.due(now)) return;
  final clientId = driveBackupClientId(settings);
  if (clientId == null) return;
  final client = http.Client();
  try {
    final bytes = await locator<BackupService>().build(now: now);
    await DriveBackup(
      client,
      settings,
      clientId: clientId,
    ).upload(bytes, now: now);
  } catch (_) {
    // Offline or signed out: the next opening tries again.
  } finally {
    client.close();
  }
}
