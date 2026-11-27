import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Connection details for the machine that will host the sync service.
class LocalServerCredentials {
  final String host;
  final int port;
  final String user;
  final String? password;
  final String? privateKeyPem;
  final String? passphrase;
  final String? _sudoPassword;

  const LocalServerCredentials({
    required this.host,
    this.port = 22,
    required this.user,
    this.password,
    this.privateKeyPem,
    this.passphrase,
    String? sudoPassword,
  }) : _sudoPassword = sudoPassword;

  /// Password given to `sudo`; defaults to the SSH password.
  String? get sudoPassword => _sudoPassword ?? password;
}

class LocalServerSetupResult {
  final Uri baseUrl;
  final String token;

  /// Non-fatal remarks collected during setup (e.g. unexpected OS).
  final List<String> warnings;

  const LocalServerSetupResult({
    required this.baseUrl,
    required this.token,
    this.warnings = const [],
  });
}

enum LocalServerSetupStep {
  connecting,
  checkingSystem,
  installingPython,
  uploading,
  configuring,
  starting,
  verifying,
  done,
}

class LocalServerSetupException implements Exception {
  final LocalServerSetupStep step;
  final String message;
  final bool authFailed;

  const LocalServerSetupException(
    this.step,
    this.message, {
    this.authFailed = false,
  });

  @override
  String toString() => 'LocalServerSetupException(${step.name}): $message';
}

class RemoteResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const RemoteResult(this.exitCode, {this.stdout = '', this.stderr = ''});

  bool get ok => exitCode == 0;
}

/// Minimal remote command runner so the setup logic can be tested without SSH.
abstract class RemoteShell {
  Future<RemoteResult> run(String command, {String? stdin});

  Future<void> close();
}

typedef RemoteShellConnector =
    Future<RemoteShell> Function(LocalServerCredentials credentials);

/// How commands needing root privileges are executed.
enum SudoMode {
  /// Logged in as root: no sudo needed.
  root,

  /// Passwordless sudo.
  noPassword,

  /// `sudo -S`, the password is the first line of stdin.
  password,
}

/// A shell command with optional stdin payload.
class PlannedCommand {
  final LocalServerSetupStep step;
  final String command;
  final String? stdin;

  /// True if the command is run through `sudo -S` and therefore expects the
  /// sudo password as the first stdin line.
  final bool needsPassword;

  const PlannedCommand(
    this.step,
    this.command, {
    this.stdin,
    this.needsPassword = false,
  });
}

/// SSH implementation of [RemoteShell] backed by dartssh2.
class SshRemoteShell implements RemoteShell {
  final SSHClient _client;

  SshRemoteShell(this._client);

  static Future<SshRemoteShell> connect(LocalServerCredentials c) async {
    final socket = await SSHSocket.connect(
      c.host,
      c.port,
      timeout: const Duration(seconds: 15),
    );
    final pem = c.privateKeyPem?.trim();
    final hasKey = pem != null && pem.isNotEmpty;
    final client = SSHClient(
      socket,
      username: c.user,
      identities: hasKey ? SSHKeyPair.fromPem(pem, c.passphrase) : null,
      onPasswordRequest: c.password != null ? () => c.password : null,
    );
    await client.authenticated;
    return SshRemoteShell(client);
  }

  @override
  Future<RemoteResult> run(String command, {String? stdin}) async {
    final session = await _client.execute(command);
    final out = <int>[];
    final err = <int>[];
    final outDone = session.stdout.listen(out.addAll).asFuture<void>();
    final errDone = session.stderr.listen(err.addAll).asFuture<void>();
    if (stdin != null) {
      session.stdin.add(utf8.encode(stdin));
    }
    await session.stdin.close();
    await session.done;
    await Future.wait([outDone, errDone]);
    return RemoteResult(
      session.exitCode ?? (session.exitSignal != null ? 255 : 0),
      stdout: utf8.decode(out, allowMalformed: true),
      stderr: utf8.decode(err, allowMalformed: true),
    );
  }

  @override
  Future<void> close() async {
    _client.close();
    try {
      await _client.done;
    } catch (_) {}
  }
}

/// Installs / removes the EatPoint sync service on an Ubuntu/Debian machine.
class LocalServerSetup {
  static const assetPath = 'assets/server/eatpoint_sync_server.py';
  static const installDir = '/opt/eatpoint';
  static const scriptPath = '$installDir/eatpoint_sync_server.py';
  static const configDir = '/etc/eatpoint';
  static const tokenPath = '$configDir/token';
  static const dataDir = '/var/lib/eatpoint';
  static const dbPath = '$dataDir/sync.db';
  static const serviceName = 'eatpoint-sync';
  static const unitPath = '/etc/systemd/system/$serviceName.service';
  static const serviceUser = 'eatpoint';

  final RemoteShellConnector _connector;
  final Future<String> Function() _scriptLoader;
  final String Function() _tokenGenerator;

  LocalServerSetup({
    RemoteShellConnector? connector,
    Future<String> Function()? scriptLoader,
    String Function()? tokenGenerator,
  }) : _connector = connector ?? SshRemoteShell.connect,
       _scriptLoader = scriptLoader ?? (() => rootBundle.loadString(assetPath)),
       _tokenGenerator = tokenGenerator ?? generateToken;

  // ---------------------------------------------------------------------
  // Pure helpers
  // ---------------------------------------------------------------------

  /// 32 random bytes as 64 lowercase hex characters.
  static String generateToken([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(
      32,
      (_) => r.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// POSIX single-quote escaping.
  static String shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// Wraps [script] so it runs as root. The password is never part of the
  /// command: with [SudoMode.password] sudo reads it from stdin (`-S`).
  static String sudoCommand(String script, SudoMode mode) {
    final sh = 'sh -c ${shellQuote(script)}';
    switch (mode) {
      case SudoMode.root:
        return sh;
      case SudoMode.noPassword:
        return 'sudo -n $sh';
      case SudoMode.password:
        return "sudo -S -p '' -k $sh";
    }
  }

  static PlannedCommand _root(
    LocalServerSetupStep step,
    String script,
    SudoMode mode, {
    String? stdin,
  }) => PlannedCommand(
    step,
    sudoCommand(script, mode),
    stdin: stdin,
    needsPassword: mode == SudoMode.password,
  );

  static String unitFile(int port) =>
      '''[Unit]
Description=EatPoint sync service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$serviceUser
Group=$serviceUser
ExecStart=/usr/bin/env python3 $scriptPath --db $dbPath --port $port --token-file $tokenPath
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$dataDir
PrivateTmp=true

[Install]
WantedBy=multi-user.target
''';

  static const String osReleaseCommand =
      r'lsb_release -is 2>/dev/null || (. /etc/os-release 2>/dev/null && echo "$ID")';

  /// True for Ubuntu / Debian style distribution names.
  static bool isDebianLike(String osName) {
    final n = osName.trim().toLowerCase();
    return n.contains('ubuntu') ||
        n.contains('debian') ||
        n.contains('raspbian') ||
        n.contains('mint');
  }

  static const String idCommand = 'id -u';
  static const String sudoProbeNoPassword = 'sudo -n true';
  static const String pythonCheckCommand = 'command -v python3';

  static String sudoProbeCommand(SudoMode mode) =>
      sudoCommand('true', mode); // used to validate the sudo password

  static PlannedCommand installPythonCommand(SudoMode mode) => _root(
    LocalServerSetupStep.installingPython,
    'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq; '
    'apt-get install -y python3',
    mode,
  );

  static PlannedCommand ufwStatusCommand(SudoMode mode) => _root(
    LocalServerSetupStep.starting,
    'command -v ufw >/dev/null && ufw status',
    mode,
  );

  static bool isUfwActive(RemoteResult r) =>
      r.ok && RegExp(r'^Status:\s*active', multiLine: true).hasMatch(r.stdout);

  static PlannedCommand ufwAllowCommand(SudoMode mode, int port) =>
      _root(LocalServerSetupStep.starting, 'ufw allow $port/tcp', mode);

  static String healthCheckCommand(int port) =>
      'for i in 1 2 3 4 5 6 7 8; do '
      'curl -fsS --max-time 3 http://127.0.0.1:$port/health && exit 0; '
      'sleep 1; done; exit 1';

  /// Commands for the upload / configure / start phases (without ufw and
  /// health check, which depend on remote state).
  static List<PlannedCommand> installCommands({
    required SudoMode sudo,
    required int port,
    required String token,
    required String serverScript,
  }) {
    const up = LocalServerSetupStep.uploading;
    const cfg = LocalServerSetupStep.configuring;
    const start = LocalServerSetupStep.starting;
    return [
      _root(up, 'mkdir -p $installDir', sudo),
      _root(
        up,
        'umask 022; tee $scriptPath >/dev/null && chmod 644 $scriptPath',
        sudo,
        stdin: serverScript,
      ),
      _root(
        cfg,
        'id -u $serviceUser >/dev/null 2>&1 || '
        'useradd --system --no-create-home --shell /usr/sbin/nologin '
        '$serviceUser',
        sudo,
      ),
      _root(
        cfg,
        'install -d -o $serviceUser -g $serviceUser -m 750 $dataDir && '
        'install -d -m 755 $configDir',
        sudo,
      ),
      _root(
        cfg,
        'umask 077; tee $tokenPath >/dev/null && '
        'chown $serviceUser:$serviceUser $tokenPath && '
        'chmod 600 $tokenPath',
        sudo,
        stdin: '$token\n',
      ),
      _root(
        cfg,
        'umask 022; tee $unitPath >/dev/null',
        sudo,
        stdin: unitFile(port),
      ),
      _root(
        start,
        'systemctl daemon-reload && systemctl enable --now $serviceName && '
        'systemctl restart $serviceName',
        sudo,
      ),
    ];
  }

  static List<PlannedCommand> uninstallCommands({
    required SudoMode sudo,
    int port = 8787,
    bool deleteData = false,
  }) {
    const s = LocalServerSetupStep.configuring;
    return [
      _root(
        s,
        'systemctl disable --now $serviceName 2>/dev/null; '
        'rm -f $unitPath; systemctl daemon-reload; '
        'rm -rf $installDir $configDir; true',
        sudo,
      ),
      _root(
        s,
        'if command -v ufw >/dev/null && '
        'ufw status | grep -q "^Status: active"; then '
        'ufw delete allow $port/tcp; fi; true',
        sudo,
      ),
      if (deleteData)
        _root(
          s,
          'rm -rf $dataDir; '
          'id -u $serviceUser >/dev/null 2>&1 && userdel $serviceUser; true',
          sudo,
        ),
    ];
  }

  // ---------------------------------------------------------------------
  // Execution
  // ---------------------------------------------------------------------

  Future<LocalServerSetupResult> install(
    LocalServerCredentials c, {
    int servicePort = 8787,
    void Function(LocalServerSetupStep step)? onStep,
  }) async {
    final warnings = <String>[];
    final shell = await _connect(c, onStep);
    try {
      onStep?.call(LocalServerSetupStep.checkingSystem);
      final mode = await _detectSudo(shell, c);

      final os = await _try(shell, osReleaseCommand);
      if (!os.ok || !isDebianLike(os.stdout)) {
        warnings.add(
          'Unrecognised operating system '
          '"${os.stdout.trim()}"; continuing anyway.',
        );
      }

      final py = await _try(shell, pythonCheckCommand);
      if (!py.ok) {
        onStep?.call(LocalServerSetupStep.installingPython);
        await _exec(
          shell,
          installPythonCommand(mode),
          c,
          'Could not install python3 (apt-get failed)',
        );
      }

      final script = await _scriptLoader();
      final token = _tokenGenerator();
      final plan = installCommands(
        sudo: mode,
        port: servicePort,
        token: token,
        serverScript: script,
      );

      LocalServerSetupStep? current;
      for (final cmd in plan) {
        if (cmd.step != current) {
          current = cmd.step;
          onStep?.call(current);
        }
        await _exec(shell, cmd, c, 'Step "${cmd.step.name}" failed');
      }

      // Firewall: only when ufw is active.
      final ufw = await _runPlanned(shell, ufwStatusCommand(mode), c);
      if (isUfwActive(ufw)) {
        await _exec(
          shell,
          ufwAllowCommand(mode, servicePort),
          c,
          'Could not open port $servicePort in ufw',
        );
      }

      onStep?.call(LocalServerSetupStep.verifying);
      final health = await shell.run(healthCheckCommand(servicePort));
      if (!health.ok || !health.stdout.contains('true')) {
        throw LocalServerSetupException(
          LocalServerSetupStep.verifying,
          'The service did not answer on port $servicePort. '
                  '${_clean(health.stderr, c)}'
              .trim(),
        );
      }

      onStep?.call(LocalServerSetupStep.done);
      return LocalServerSetupResult(
        baseUrl: Uri(scheme: 'http', host: c.host, port: servicePort),
        token: token,
        warnings: warnings,
      );
    } finally {
      await shell.close();
    }
  }

  Future<void> uninstall(
    LocalServerCredentials c, {
    int servicePort = 8787,
    bool deleteData = false,
    void Function(LocalServerSetupStep step)? onStep,
  }) async {
    final shell = await _connect(c, onStep);
    try {
      onStep?.call(LocalServerSetupStep.checkingSystem);
      final mode = await _detectSudo(shell, c);
      onStep?.call(LocalServerSetupStep.configuring);
      for (final cmd in uninstallCommands(
        sudo: mode,
        port: servicePort,
        deleteData: deleteData,
      )) {
        await _exec(shell, cmd, c, 'Removal failed');
      }
      onStep?.call(LocalServerSetupStep.done);
    } finally {
      await shell.close();
    }
  }

  Future<RemoteShell> _connect(
    LocalServerCredentials c,
    void Function(LocalServerSetupStep)? onStep,
  ) async {
    onStep?.call(LocalServerSetupStep.connecting);
    try {
      return await _connector(c);
    } on LocalServerSetupException {
      rethrow;
    } on SSHAuthError catch (e) {
      throw LocalServerSetupException(
        LocalServerSetupStep.connecting,
        'Authentication failed: ${e.toString()}',
        authFailed: true,
      );
    } on SocketException catch (e) {
      throw LocalServerSetupException(
        LocalServerSetupStep.connecting,
        'Cannot reach ${c.host}:${c.port}: ${e.message}',
      );
    } on TimeoutException {
      throw LocalServerSetupException(
        LocalServerSetupStep.connecting,
        'Timed out connecting to ${c.host}:${c.port}',
      );
    } catch (e) {
      throw LocalServerSetupException(
        LocalServerSetupStep.connecting,
        _clean(e.toString(), c),
      );
    }
  }

  Future<SudoMode> _detectSudo(
    RemoteShell shell,
    LocalServerCredentials c,
  ) async {
    const step = LocalServerSetupStep.checkingSystem;
    final id = await _try(shell, idCommand);
    if (id.ok && id.stdout.trim() == '0') return SudoMode.root;

    final nopass = await _try(shell, sudoProbeNoPassword);
    if (nopass.ok) return SudoMode.noPassword;

    final pw = c.sudoPassword;
    if (pw == null || pw.isEmpty) {
      throw const LocalServerSetupException(
        step,
        'sudo needs a password but none was provided',
        authFailed: true,
      );
    }
    final probe = await shell.run(
      sudoProbeCommand(SudoMode.password),
      stdin: '$pw\n',
    );
    if (!probe.ok) {
      throw const LocalServerSetupException(
        step,
        'sudo rejected the password (or the user may not use sudo)',
        authFailed: true,
      );
    }
    return SudoMode.password;
  }

  Future<RemoteResult> _try(RemoteShell shell, String command) async {
    try {
      return await shell.run(command);
    } catch (_) {
      return const RemoteResult(255);
    }
  }

  Future<RemoteResult> _runPlanned(
    RemoteShell shell,
    PlannedCommand cmd,
    LocalServerCredentials c,
  ) async {
    var stdin = cmd.stdin;
    if (cmd.needsPassword) {
      stdin = '${c.sudoPassword ?? ''}\n${stdin ?? ''}';
    }
    try {
      return await shell.run(cmd.command, stdin: stdin);
    } catch (_) {
      return const RemoteResult(255);
    }
  }

  Future<void> _exec(
    RemoteShell shell,
    PlannedCommand cmd,
    LocalServerCredentials c,
    String failure,
  ) async {
    var stdin = cmd.stdin;
    if (cmd.needsPassword) {
      stdin = '${c.sudoPassword ?? ''}\n${stdin ?? ''}';
    }
    final RemoteResult r;
    try {
      r = await shell.run(cmd.command, stdin: stdin);
    } catch (e) {
      throw LocalServerSetupException(
        cmd.step,
        '$failure: ${_clean(e.toString(), c)}',
      );
    }
    if (!r.ok) {
      final detail = _clean(r.stderr, c);
      throw LocalServerSetupException(
        cmd.step,
        detail.isEmpty ? failure : '$failure: $detail',
      );
    }
  }

  /// Removes secrets from [text] and trims it to a readable size.
  static String _clean(String text, LocalServerCredentials c) {
    var t = text;
    for (final secret in [c.password, c.sudoPassword, c.passphrase]) {
      if (secret != null && secret.isNotEmpty) t = t.replaceAll(secret, '***');
    }
    t = t.trim();
    return t.length > 300 ? t.substring(t.length - 300) : t;
  }
}
