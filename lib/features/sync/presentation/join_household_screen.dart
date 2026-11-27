import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_sync_service.dart';
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

class _JoinHouseholdScreenState extends State<JoinHouseholdScreen> {
  late final HouseholdStore _store = widget.store ?? locator<HouseholdStore>();
  bool _busy = false;

  Future<void> _handle(String text) async {
    if (_busy) return;
    final s = S.of(context);
    final invite = HouseholdInvite.decode(text.trim());
    if (invite == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.householdInvalidInvite)));
      return;
    }
    _busy = true;
    final navigator = Navigator.of(context);
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
          if (widget.showScanner)
            MobileScanner(
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
                child: Text(
                  s.householdJoin,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
