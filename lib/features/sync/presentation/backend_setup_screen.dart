import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/sync/data/backends/supabase_sync_backend.dart';
import 'package:opennutritracker/features/sync/data/backends/sync_backend_factory.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/data/local_server/local_server_setup.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_crypto.dart';
import 'package:opennutritracker/features/sync/domain/household_sync_service.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:opennutritracker/features/sync/presentation/storage_labels.dart';
import 'package:opennutritracker/features/sync/data/backends/google_drive_sync_backend.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

/// Picks where the household's data is kept, tests it and creates the
/// household.
class BackendSetupScreen extends StatefulWidget {
  final String memberName;
  final http.Client? client;
  final LocalServerSetup? localServerSetup;
  final HouseholdStore? store;
  final HouseholdSyncService? syncService;

  const BackendSetupScreen({
    super.key,
    required this.memberName,
    this.client,
    this.localServerSetup,
    this.store,
    this.syncService,
  });

  @override
  State<BackendSetupScreen> createState() => _BackendSetupScreenState();
}

class _BackendSetupScreenState extends State<BackendSetupScreen> {
  late final http.Client _client = widget.client ?? http.Client();
  late final LocalServerSetup _setup =
      widget.localServerSetup ?? LocalServerSetup();
  late final HouseholdStore _store = widget.store ?? locator<HouseholdStore>();

  SyncBackendKind _kind = SyncBackendKind.supabase;
  bool _installLocal = false;
  bool _busy = false;
  String? _installStep;

  final _supabaseUrl = TextEditingController();
  final _supabaseKey = TextEditingController();
  final _supabaseToken = TextEditingController();
  final _webdavUrl = TextEditingController();
  final _webdavUser = TextEditingController();
  final _webdavPassword = TextEditingController();
  final _localUrl = TextEditingController();
  final _localToken = TextEditingController();
  final _sshHost = TextEditingController();
  final _sshPort = TextEditingController(text: '22');
  final _sshUser = TextEditingController();
  final _sshPassword = TextEditingController();
  final _sshKey = TextEditingController();
  // EatPoint: Google Drive.
  final _driveClientId = TextEditingController(
    text: GoogleDriveAuth.builtInWebClientId,
  );
  final _driveShareWith = TextEditingController();
  String? _driveEmail;

  @override
  void dispose() {
    for (final c in [
      _supabaseUrl,
      _supabaseKey,
      _supabaseToken,
      _webdavUrl,
      _webdavUser,
      _webdavPassword,
      _localUrl,
      _localToken,
      _sshHost,
      _sshPort,
      _sshUser,
      _sshPassword,
      _sshKey,
    ]) {
      c.dispose();
    }
    if (widget.client == null) _client.close();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  (SyncBackendConfig, String?)? _buildConfig() {
    switch (_kind) {
      case SyncBackendKind.supabase:
        return (
          SyncBackendConfig(kind: _kind, url: _supabaseUrl.text.trim()),
          _supabaseKey.text.trim(),
        );
      case SyncBackendKind.webdav:
        return (
          SyncBackendConfig(
            kind: _kind,
            url: _webdavUrl.text.trim(),
            user: _webdavUser.text.trim(),
          ),
          _webdavPassword.text,
        );
      case SyncBackendKind.localServer:
        return (
          SyncBackendConfig(kind: _kind, url: _localUrl.text.trim()),
          _localToken.text.trim(),
        );
      case SyncBackendKind.googleDrive:
        // The folder is created in _testAndCreate, once signed in.
        return null;
    }
  }

  Future<void> _driveSignIn() async {
    final s = S.of(context);
    final clientId = _driveClientId.text.trim();
    if (clientId.isEmpty) return;
    setState(() => _busy = true);
    try {
      final email = await GoogleDriveAuth.signIn(clientId);
      if (mounted) setState(() => _driveEmail = email);
    } catch (e) {
      if (mounted) _snack(s.householdConnectionFailed(syncFailureReason(s, e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Creates the household's folder in Drive and shares it, then the
  /// config that points at it.
  Future<SyncBackendConfig?> _driveConfig() async {
    final s = S.of(context);
    if (_driveEmail == null) {
      _snack(s.householdDriveNeedsSignIn);
      return null;
    }
    final clientId = _driveClientId.text.trim();
    final token = await GoogleDriveAuth.accessToken(clientId);
    final folderId = await GoogleDriveSyncBackend.createFolder(
      _client,
      token,
      s.householdDriveFolderName,
    );
    // One or more Google accounts, separated by commas, spaces or `;`.
    final shareWith = _driveShareWith.text
        .split(RegExp(r'[\s,;]+'))
        .where((e) => e.contains('@'))
        .toSet();
    for (final email in shareWith) {
      await GoogleDriveSyncBackend.shareFolder(_client, token, folderId, email);
    }
    return SyncBackendConfig(kind: _kind, url: folderId, user: clientId);
  }

  Future<void> _createDatabase() async {
    final s = S.of(context);
    final ref = projectRef();
    if (ref == null || _supabaseToken.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await SupabaseSyncBackend.runSetupWithAccessToken(
        _client,
        projectRef: ref,
        personalAccessToken: _supabaseToken.text.trim(),
      );
      if (mounted) _snack(s.householdSupabaseDbCreated);
    } catch (e) {
      if (mounted) {
        _snack(s.householdConnectionFailed(syncFailureReason(s, e)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? projectRef() {
    final uri = Uri.tryParse(_supabaseUrl.text.trim());
    return uri == null ? null : SupabaseSyncBackend.projectRefFromUrl(uri);
  }

  Future<void> _install() async {
    final s = S.of(context);
    setState(() {
      _busy = true;
      _installStep = null;
    });
    try {
      final key = _sshKey.text.trim();
      final result = await _setup.install(
        LocalServerCredentials(
          host: _sshHost.text.trim(),
          port: int.tryParse(_sshPort.text.trim()) ?? 22,
          user: _sshUser.text.trim(),
          password: _sshPassword.text.isEmpty ? null : _sshPassword.text,
          privateKeyPem: key.isEmpty ? null : key,
        ),
        onStep: (step) {
          if (mounted) setState(() => _installStep = step.name);
        },
      );
      if (!mounted) return;
      setState(() {
        _localUrl.text = result.baseUrl.toString();
        _localToken.text = result.token;
        _installLocal = false;
      });
      _snack(s.householdInstallDone);
    } on LocalServerSetupException catch (e) {
      if (mounted) {
        _snack(
          s.householdConnectionFailed(
            e.authFailed ? s.householdWrongCredentials : e.message,
          ),
        );
      }
    } catch (e) {
      if (mounted) _snack(s.householdConnectionFailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _installStep = null;
        });
      }
    }
  }

  Future<void> _testAndCreate() async {
    final s = S.of(context);
    final navigator = Navigator.of(context);
    SyncBackendConfig config;
    String? secret;
    if (_kind == SyncBackendKind.googleDrive) {
      setState(() => _busy = true);
      try {
        final drive = await _driveConfig();
        if (drive == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        config = drive;
      } catch (e) {
        if (mounted) {
          _snack(s.householdConnectionFailed(syncFailureReason(s, e)));
          setState(() => _busy = false);
        }
        return;
      }
    } else {
      final built = _buildConfig();
      if (built == null) return;
      (config, secret) = built;
    }
    setState(() => _busy = true);
    try {
      final householdId = Household.randomHexId();
      final backend = createSyncBackend(
        _client,
        config,
        householdId: householdId,
        secret: secret,
      );
      await backend.testConnection();
      await _store.writeKey(HouseholdKey.generate());
      await _store.writeBackendSecret(secret);
      await _store.saveHousehold(
        Household(
          householdId: householdId,
          memberId: Household.randomHexId(8),
          memberName: widget.memberName,
          backend: config,
        ),
      );
      try {
        await (widget.syncService ?? locator<HouseholdSyncService>()).syncNow();
      } catch (_) {
        // Created; the first sync can be retried from the household screen.
      }
      if (navigator.mounted) navigator.pop(true);
    } catch (e) {
      if (mounted) {
        _snack(s.householdConnectionFailed(syncFailureReason(s, e)));
        setState(() => _busy = false);
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String id, {
    bool obscure = false,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: Dimens.spacing12),
    child: Semantics(
      identifier: id,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        maxLines: maxLines,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final options = <(SyncBackendKind, String, String)>[
      (
        SyncBackendKind.supabase,
        s.householdStorageSupabase,
        s.householdStorageSupabaseSubtitle,
      ),
      (
        SyncBackendKind.webdav,
        s.householdStorageWebdav,
        s.householdStorageWebdavSubtitle,
      ),
      (
        SyncBackendKind.localServer,
        s.householdStorageLocal,
        s.householdStorageLocalSubtitle,
      ),
      (
        SyncBackendKind.googleDrive,
        s.householdStorageDrive,
        s.householdStorageDriveSubtitle,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.householdCreate)),
      body: ListView(
        padding: const EdgeInsets.all(Dimens.spacing16),
        children: [
          Text(
            s.householdStorageTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          RadioGroup<SyncBackendKind>(
            groupValue: _kind,
            onChanged: (k) {
              if (k != null && !_busy) setState(() => _kind = k);
            },
            child: Column(
              children: [
                for (final (kind, title, subtitle) in options)
                  Semantics(
                    identifier: 'household-storage-${_kebab(kind)}',
                    child: RadioListTile<SyncBackendKind>(
                      contentPadding: EdgeInsets.zero,
                      value: kind,
                      title: Text(title),
                      subtitle: Text(subtitle),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          ..._kindFields(context),
          const SizedBox(height: Dimens.spacing24),
          Semantics(
            identifier: 'household-test-and-create',
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: scheme.primary,
              ),
              onPressed:
                  _busy ||
                      (_kind == SyncBackendKind.googleDrive &&
                          _driveEmail == null)
                  ? null
                  : _testAndCreate,
              child: Text(s.householdTestAndCreate),
            ),
          ),
        ],
      ),
    );
  }

  static String _kebab(SyncBackendKind kind) {
    switch (kind) {
      case SyncBackendKind.supabase:
        return 'supabase';
      case SyncBackendKind.webdav:
        return 'webdav';
      case SyncBackendKind.localServer:
        return 'local-server';
      case SyncBackendKind.googleDrive:
        return 'google-drive';
    }
  }

  List<Widget> _kindFields(BuildContext context) {
    final s = S.of(context);
    switch (_kind) {
      case SyncBackendKind.supabase:
        return [
          _field(
            _supabaseUrl,
            s.householdSupabaseUrl,
            'household-supabase-url',
            keyboardType: TextInputType.url,
          ),
          _field(
            _supabaseKey,
            s.householdSupabaseAnonKey,
            'household-supabase-anon-key',
          ),
          _field(
            _supabaseToken,
            s.householdSupabaseToken,
            'household-supabase-token',
            obscure: true,
          ),
          const SizedBox(height: Dimens.spacing12),
          Semantics(
            identifier: 'household-supabase-create-db',
            child: OutlinedButton(
              onPressed: _busy ? null : _createDatabase,
              child: Text(s.householdSupabaseCreateDb),
            ),
          ),
          Semantics(
            identifier: 'household-supabase-copy-sql',
            child: TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: SupabaseSyncBackend.setupSql),
                );
              },
              child: Text(s.householdSupabaseCopySql),
            ),
          ),
        ];
      case SyncBackendKind.webdav:
        return [
          _field(
            _webdavUrl,
            s.householdWebdavUrl,
            'household-webdav-url',
            keyboardType: TextInputType.url,
          ),
          _field(_webdavUser, s.householdWebdavUser, 'household-webdav-user'),
          _field(
            _webdavPassword,
            s.householdPassword,
            'household-webdav-password',
            obscure: true,
          ),
        ];
      case SyncBackendKind.localServer:
        return [
          Semantics(
            identifier: 'household-local-mode',
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(s.householdLocalHaveServer),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(s.householdLocalInstall),
                ),
              ],
              selected: {_installLocal},
              onSelectionChanged: _busy
                  ? null
                  : (v) => setState(() => _installLocal = v.first),
            ),
          ),
          if (!_installLocal) ...[
            _field(
              _localUrl,
              s.householdLocalUrl,
              'household-local-url',
              keyboardType: TextInputType.url,
            ),
            _field(_localToken, s.householdLocalToken, 'household-local-token'),
          ] else ...[
            _field(_sshHost, s.householdSshHost, 'household-ssh-host'),
            _field(
              _sshPort,
              s.householdSshPort,
              'household-ssh-port',
              keyboardType: TextInputType.number,
            ),
            _field(_sshUser, s.householdSshUser, 'household-ssh-user'),
            _field(
              _sshPassword,
              s.householdPassword,
              'household-ssh-password',
              obscure: true,
            ),
            _field(
              _sshKey,
              s.householdSshKey,
              'household-ssh-key',
              maxLines: 5,
            ),
            const SizedBox(height: Dimens.spacing12),
            Semantics(
              identifier: 'household-install',
              child: FilledButton.tonal(
                onPressed: _busy ? null : _install,
                child: Text(s.householdInstall),
              ),
            ),
            if (_installStep != null)
              Padding(
                padding: const EdgeInsets.only(top: Dimens.spacing8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: Dimens.spacing12),
                    Expanded(
                      child: Text(s.householdInstallStep(_installStep!)),
                    ),
                  ],
                ),
              ),
          ],
        ];
      case SyncBackendKind.googleDrive:
        return [
          _field(
            _driveClientId,
            s.householdDriveClientId,
            'household-drive-client-id',
          ),
          Padding(
            padding: const EdgeInsets.only(top: Dimens.spacing4),
            child: Text(
              s.householdDriveClientIdHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.help_outline_rounded),
              label: Text(s.householdDriveGuide),
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://github.com/Grohle/EatPoint/blob/main/docs/google-drive.md',
                ),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing8),
          if (_driveEmail == null)
            Semantics(
              identifier: 'household-drive-sign-in',
              child: OutlinedButton.icon(
                icon: const Icon(Icons.login_rounded),
                label: Text(s.householdDriveSignIn),
                onPressed: _busy ? null : _driveSignIn,
              ),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_rounded),
              title: Text(s.householdDriveSignedIn(_driveEmail!)),
            ),
          _field(
            _driveShareWith,
            s.householdDriveShareWith,
            'household-drive-share-with',
            keyboardType: TextInputType.emailAddress,
          ),
          Padding(
            padding: const EdgeInsets.only(top: Dimens.spacing4),
            child: Text(
              s.householdDriveShareHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ];
    }
  }
}
