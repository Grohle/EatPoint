import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/safe_url_launcher.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/update_checker.dart';
import '../data/update_store.dart';
import '../domain/app_update.dart';

final _log = Logger('AppUpdates');

/// The APK type this build is, so the download matches it.
List<String> currentAbis() => switch (Abi.current()) {
  Abi.androidArm64 => const ['arm64-v8a'],
  Abi.androidArm => const ['armeabi-v7a'],
  Abi.androidX64 => const ['x86_64'],
  _ => const [],
};

Future<AppUpdate?> _check(UpdateChecker checker) async {
  final info = await PackageInfo.fromPlatform();
  return checker.check(installed: info.version, abis: currentAbis());
}

/// On opening the app: looks quietly for a newer release and offers it.
/// Says nothing when offline, up to date, turned off, or already offered
/// in the last day.
Future<void> maybeOfferUpdate(
  BuildContext context, {
  UpdateChecker? checker,
  UpdateStore? store,
}) async {
  if (!Platform.isAndroid) return;
  final updates = store ?? locator<UpdateStore>();
  if (!updates.autoCheck) return;
  final client = http.Client();
  AppUpdate? update;
  try {
    update = await _check(checker ?? UpdateChecker(client));
  } catch (e) {
    _log.fine('Update check skipped: $e');
    return;
  } finally {
    client.close();
  }
  if (update == null || !context.mounted) return;
  final version = update.version.toString();
  if (!updates.shouldOffer(version)) return;
  await updates.markOffered(version);
  if (!context.mounted) return;
  await showUpdateDialog(context, update);
}

/// "Version X is available": the start of its notes and a download button.
Future<void> showUpdateDialog(BuildContext context, AppUpdate update) {
  final s = S.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.system_update_rounded),
      title: Text(s.updateAvailableTitle(update.version.toString())),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.updateAvailableBody),
            if (_summary(update.notes).isNotEmpty) ...[
              const SizedBox(height: Dimens.spacing12),
              Text(
                _summary(update.notes),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.updateLater),
        ),
        TextButton(
          onPressed: () => tryLaunchExternalUrl(update.pageUrl),
          child: Text(s.updateNotes),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await tryLaunchExternalUrl(update.downloadUrl);
          },
          child: Text(s.updateDownload),
        ),
      ],
    ),
  );
}

/// The "What's new" part of the notes, as plain lines, kept short.
String _summary(String notes) {
  final lines = notes
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('>'))
      .toList();
  final start = lines.indexWhere((l) => l.startsWith('## '));
  final body = <String>[];
  for (final line in lines.skip(start < 0 ? 0 : start + 1)) {
    if (line.startsWith('## ')) break;
    body.add(
      line
          .replaceAll(RegExp(r'\*\*|`'), '')
          .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
          .replaceFirst(RegExp(r'^- '), '• '),
    );
    if (body.length >= 8) break;
  }
  return body.join('\n');
}

/// Settings: the installed version, the "check when opening" switch and a
/// "Check now" button.
class UpdateSettingsSheet extends StatefulWidget {
  final UpdateStore? store;
  final UpdateChecker? checker;

  const UpdateSettingsSheet({super.key, this.store, this.checker});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const UpdateSettingsSheet(),
  );

  @override
  State<UpdateSettingsSheet> createState() => _UpdateSettingsSheetState();
}

class _UpdateSettingsSheetState extends State<UpdateSettingsSheet> {
  late final UpdateStore _store = widget.store ?? locator<UpdateStore>();
  String? _installed;
  bool _checking = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _installed = info.version);
    });
  }

  Future<void> _checkNow() async {
    final s = S.of(context);
    setState(() {
      _checking = true;
      _result = null;
    });
    final client = http.Client();
    try {
      final update = await _check(widget.checker ?? UpdateChecker(client));
      if (!mounted) return;
      if (update == null) {
        setState(() => _result = s.updateUpToDate);
      } else {
        setState(() {
          _result = null;
          _checking = false;
        });
        await _store.markOffered(update.version.toString());
        if (mounted) await showUpdateDialog(context, update);
      }
    } catch (_) {
      if (mounted) setState(() => _result = s.updateCheckFailed);
    } finally {
      client.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing16,
          0,
          Dimens.spacing16,
          Dimens.spacing16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.updatesTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Dimens.spacing4),
            Text(s.updateInstalledVersion(_installed ?? '…')),
            const SizedBox(height: Dimens.spacing8),
            Semantics(
              identifier: 'updates-auto-check',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.updateAutoCheck),
                subtitle: Text(s.updateAutoCheckHint),
                value: _store.autoCheck,
                onChanged: (value) async {
                  await _store.setAutoCheck(value);
                  if (mounted) setState(() {});
                },
              ),
            ),
            const SizedBox(height: Dimens.spacing8),
            Semantics(
              identifier: 'updates-check-now',
              child: FilledButton.icon(
                onPressed: _checking ? null : _checkNow,
                icon: _checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(s.updateCheckNow),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: Dimens.spacing8),
              Text(_result!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
