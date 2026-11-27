import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_sync_service.dart';
import 'package:opennutritracker/features/sync/data/backends/google_drive_sync_backend.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:opennutritracker/features/sync/presentation/storage_labels.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Scans (or takes pasted) invite text and joins that household.
class JoinHouseholdScreen extends StatefulWidget {
  final String memberName;
  final HouseholdStore? store;
  final HouseholdSyncService? syncService;

  /// Set to false to skip the camera (tests, devices without one).
  final bool showScanner;

  const JoinHouseholdScreen({
    super.key,
    required this.memberName,
    this.store,
    this.syncService,
    this.showScanner = true,
  });

  @override
  State<JoinHouseholdScreen> createState() => _JoinHouseholdScreenState();
}

class _JoinHouseholdScreenState extends State<JoinHouseholdScreen>
    with WidgetsBindingObserver {
  late final HouseholdStore _store = widget.store ?? locator<HouseholdStore>();
  bool _busy = false;

  // EatPoint: an owned controller, like the barcode scanner, so the camera
  // is started (and asks for permission) reliably and stops in background.
  MobileScannerController? _camera;

  @override
  void initState() {
    super.initState();
    if (widget.showScanner) {
      _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void dispose() {
    if (_camera != null) {
      WidgetsBinding.instance.removeObserver(this);
      _camera!.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (camera == null || !camera.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        camera.stop();
      case AppLifecycleState.resumed:
        camera.start();
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _handle(String text) async {
    if (_busy) return;
    final s = S.of(context);
    final invite = _decodeInvite(text);
    if (invite == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.householdInvalidInvite)));
      return;
    }
    _busy = true;
    final navigator = Navigator.of(context);
    // EatPoint: a Drive household needs this member's Google account.
    if (invite.backend.kind == SyncBackendKind.googleDrive) {
      try {
        await GoogleDriveAuth.signIn(
          invite.backend.user ?? GoogleDriveAuth.builtInWebClientId,
        );
      } catch (e) {
        _busy = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                s.householdConnectionFailed(syncFailureReason(s, e)),
              ),
            ),
          );
        }
        return;
      }
    }
    await _store.writeKey(invite.key);
    await _store.writeBackendSecret(invite.backendSecret);
    await _store.saveHousehold(
      Household(
        householdId: invite.householdId,
        memberId: Household.randomHexId(8),
        memberName: widget.memberName,
        backend: invite.backend,
      ),
    );
    try {
      await (widget.syncService ?? locator<HouseholdSyncService>()).syncNow();
    } catch (_) {
      // The household is saved; the user can retry from the screen.
    }
    if (navigator.mounted) navigator.pop(true);
  }

  /// The invite may come inside a longer chat or email message: take the
  /// JSON object out of it.
  static HouseholdInvite? _decodeInvite(String text) {
    final trimmed = text.trim();
    final direct = HouseholdInvite.decode(trimmed);
    if (direct != null) return direct;
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return HouseholdInvite.decode(trimmed.substring(start, end + 1));
  }

  Future<void> _paste() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteDialog(),
    );
    if (text != null && text.trim().isNotEmpty) await _handle(text);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.householdJoin),
        actions: [
          Semantics(
            identifier: 'household-paste-invite',
            child: TextButton(
              onPressed: _paste,
              child: Text(MaterialLocalizations.of(context).pasteButtonLabel),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_camera != null)
            MobileScanner(
              controller: _camera,
              errorBuilder: (context, error) => _CameraProblem(
                message:
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? s.householdCameraDenied
                    : s.householdCameraUnavailable,
              ),
              onDetect: (capture) {
                for (final barcode in capture.barcodes) {
                  final raw = barcode.rawValue;
                  if (raw != null) {
                    _handle(raw);
                    break;
                  }
                }
              },
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(Dimens.spacing16),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.householdJoinHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: Dimens.spacing12),
                    Semantics(
                      identifier: 'household-paste-invite-button',
                      child: FilledButton.tonalIcon(
                        onPressed: _paste,
                        icon: const Icon(Icons.content_paste_rounded),
                        label: Text(s.householdPasteInvite),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the camera when it can't be used.
class _CameraProblem extends StatelessWidget {
  final String message;

  const _CameraProblem({required this.message});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.spacing24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70),
            const SizedBox(height: Dimens.spacing12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(S.of(context).householdJoin),
      content: Semantics(
        identifier: 'household-invite-text',
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(material.cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(material.okButtonLabel),
        ),
      ],
    );
  }
}
