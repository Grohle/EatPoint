import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_sync_service.dart';
import 'package:opennutritracker/features/sync/presentation/backend_setup_screen.dart';
import 'package:opennutritracker/features/sync/presentation/household_edits_switch.dart';
import 'package:opennutritracker/features/sync/presentation/join_household_screen.dart';
import 'package:opennutritracker/features/sync/presentation/member_color_picker.dart';
import 'package:opennutritracker/features/sync/presentation/member_avatar.dart';
import 'package:opennutritracker/features/sync/presentation/storage_labels.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:opennutritracker/features/sync/data/backends/google_drive_sync_backend.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Shared household: create or join one, then sync, invite and leave.
class HouseholdScreen extends StatefulWidget {
  final HouseholdStore? store;
  final HouseholdSyncService? syncService;

  const HouseholdScreen({super.key, this.store, this.syncService});

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  static const _maxNameLength = 20;

  late final HouseholdStore _store = widget.store ?? locator<HouseholdStore>();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _syncing = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _nameValid() => _formKey.currentState?.validate() ?? false;

  Future<void> _push(Widget Function(String name) builder) async {
    if (!_nameValid()) return;
    final name = _name.text.trim();
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => builder(name)));
  }

  Future<void> _sync() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing = true);
    String message;
    try {
      final service = widget.syncService ?? locator<HouseholdSyncService>();
      final result = await service.syncNow();
      if (result == null) {
        message = s.householdSynced('0');
      } else if (result.unreadable.isNotEmpty) {
        message = s.householdUnreadable('${result.unreadable.length}');
      } else {
        message = s.householdSynced('${result.membersSeen}');
      }
    } catch (e) {
      message = s.householdConnectionFailed(syncFailureReason(s, e));
    }
    if (mounted) setState(() => _syncing = false);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _invite(Household household) async {
    final key = await _store.readKey();
    final secret = await _store.readBackendSecret();
    if (key == null || !mounted) return;
    final invite = HouseholdInvite(
      householdId: household.householdId,
      key: key,
      backend: household.backend,
      backendSecret: secret,
    );
    final s = S.of(context);
    final code = invite.encode();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.householdInvite),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(Dimens.spacing8),
                // A tight size: the dialog measures its content, and the
                // QR's LayoutBuilder can't be measured.
                child: SizedBox.square(
                  dimension: 240,
                  child: QrImageView(
                    data: code,
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: Dimens.spacing12),
              Text(s.householdInviteBody),
              const SizedBox(height: Dimens.spacing12),
              // EatPoint: when the phones aren't together, send it privately.
              Wrap(
                spacing: Dimens.spacing8,
                alignment: WrapAlignment.center,
                children: [
                  Semantics(
                    identifier: 'household-invite-share',
                    child: FilledButton.tonalIcon(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text: '${s.householdInviteShareText}\n\n$code',
                          subject: s.householdInviteShareSubject,
                        ),
                      ),
                      icon: const Icon(Icons.share_rounded),
                      label: Text(s.householdInviteShare),
                    ),
                  ),
                  Semantics(
                    identifier: 'household-invite-copy',
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(ClipboardData(text: code));
                        messenger.showSnackBar(
                          SnackBar(content: Text(s.householdInviteCopied)),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(
                        MaterialLocalizations.of(context).copyButtonLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _leave() async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.householdLeave),
        content: Text(s.householdLeaveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.householdLeave),
          ),
        ],
      ),
    );
    if (confirmed == true) await _store.leave();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.householdTitle)),
      body: ValueListenableBuilder<int>(
        valueListenable: _store.revision,
        builder: (context, _, _) {
          final household = _store.getHousehold();
          return ListView(
            // Room at the end, so the last button clears any message.
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing16,
              Dimens.spacing16,
              Dimens.spacing16,
              96,
            ),
            children: household == null
                ? _notSetUp(context)
                : _setUp(context, household),
          );
        },
      ),
    );
  }

  List<Widget> _notSetUp(BuildContext context) {
    final s = S.of(context);
    return [
      Text(s.householdIntro),
      const SizedBox(height: Dimens.spacing24),
      Form(
        key: _formKey,
        child: Semantics(
          identifier: 'household-your-name',
          child: TextFormField(
            controller: _name,
            maxLength: _maxNameLength,
            decoration: InputDecoration(
              labelText: s.householdYourName,
              border: const OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? S.of(context).householdNameNeeded
                : null,
          ),
        ),
      ),
      const SizedBox(height: Dimens.spacing16),
      Semantics(
        identifier: 'household-create',
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: () =>
              _push((name) => BackendSetupScreen(memberName: name)),
          icon: const Icon(Icons.add_home_outlined),
          label: Text(s.householdCreate),
        ),
      ),
      const SizedBox(height: Dimens.spacing12),
      Semantics(
        identifier: 'household-join',
        child: FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: () =>
              _push((name) => JoinHouseholdScreen(memberName: name)),
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(s.householdJoin),
        ),
      ),
    ];
  }

  List<Widget> _setUp(BuildContext context, Household household) {
    final s = S.of(context);
    final last = household.lastSyncAt;
    final lastText = last == null
        ? s.householdNeverSynced
        : s.householdLastSync(
            '${DateFormat.yMd(Localizations.localeOf(context).toString()).format(last)} '
            '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(last))}',
          );
    final others = <String>{
      ...household.members.entries
          .where((e) => e.key != household.memberId)
          .map((e) => e.value),
      ..._store.otherMembers().map((m) => m.name),
    }.where((n) => n.isNotEmpty).toList();
    return [
      Text(
        s.householdStorageInUse(storageKindLabel(s, household.backend.kind)),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: Dimens.spacing4),
      Text(lastText),
      const SizedBox(height: Dimens.spacing16),
      Semantics(
        identifier: 'household-sync-now',
        child: FilledButton.icon(
          onPressed: _syncing ? null : _sync,
          icon: _syncing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(s.householdSyncNow),
        ),
      ),
      // EatPoint: Google may ask this member to sign in again.
      if (household.backend.kind == SyncBackendKind.googleDrive)
        Semantics(
          identifier: 'household-drive-reconnect',
          child: TextButton.icon(
            icon: const Icon(Icons.login_rounded),
            label: Text(s.householdDriveReconnect),
            onPressed: _syncing
                ? null
                : () async {
                    try {
                      await GoogleDriveAuth.signIn(
                        household.backend.user ??
                            GoogleDriveAuth.builtInWebClientId,
                      );
                    } catch (_) {}
                    if (mounted) await _sync();
                  },
          ),
        ),
      const SizedBox(height: Dimens.spacing8),
      HouseholdEditsSwitch(store: _store, contentPadding: EdgeInsets.zero),
      const SizedBox(height: Dimens.spacing16),
      MemberColorPicker(store: _store),
      const SizedBox(height: Dimens.spacing16),
      Text(s.householdMembers, style: Theme.of(context).textTheme.titleMedium),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: MemberAvatar(
          name: household.memberName,
          colourKey: household.memberId,
        ),
        title: Text(s.householdYou(household.memberName)),
      ),
      for (final name in others)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(name),
        ),
      const Divider(),
      Semantics(
        identifier: 'household-invite',
        child: OutlinedButton.icon(
          onPressed: () => _invite(household),
          icon: const Icon(Icons.qr_code),
          label: Text(s.householdInvite),
        ),
      ),
      const SizedBox(height: Dimens.spacing12),
      Semantics(
        identifier: 'household-leave',
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _leave,
          icon: const Icon(Icons.logout),
          label: Text(s.householdLeave),
        ),
      ),
    ];
  }
}
