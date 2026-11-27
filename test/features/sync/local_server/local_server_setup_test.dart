import 'package:opennutritracker/features/sync/data/local_server/local_server_setup.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

class _Call {
  final String command;
  final String? stdin;
  _Call(this.command, this.stdin);
}

class FakeShell implements RemoteShell {
  final calls = <_Call>[];
  bool root = false;
  bool nopass = false;
  bool pythonPresent = true;
  bool ufwActive = false;
  bool healthOk = true;
  String os = 'Ubuntu\n';
  bool closed = false;

  @override
  Future<RemoteResult> run(String command, {String? stdin}) async {
    calls.add(_Call(command, stdin));
    if (command == 'id -u') {
      return RemoteResult(0, stdout: root ? '0\n' : '1000\n');
    }
    if (command == 'sudo -n true') return RemoteResult(nopass ? 0 : 1);
    if (command == LocalServerSetup.osReleaseCommand) {
      return RemoteResult(0, stdout: os);
    }
    if (command == 'command -v python3') {
      return RemoteResult(pythonPresent ? 0 : 1);
    }
    if (command.contains('ufw status')) {
      return RemoteResult(
        0,
        stdout: ufwActive ? 'Status: active\n' : 'Status: inactive\n',
      );
    }
    if (command.contains('127.0.0.1')) {
      return healthOk
          ? const RemoteResult(0, stdout: '{"ok": true, "version": "1"}')
          : const RemoteResult(1, stderr: 'curl: (7) refused');
    }
    return const RemoteResult(0);
  }

  @override
  Future<void> close() async => closed = true;
}

const _creds = LocalServerCredentials(
  host: '192.168.1.50',
  user: 'bob',
  password: 'p4ss w0rd\'s',
);

LocalServerSetup _setup(FakeShell shell) => LocalServerSetup(
  connector: (_) async => shell,
  scriptLoader: () async => '# fake script\n',
  tokenGenerator: () => 'f' * 64,
);

void main() {
  test('generateToken is 64 hex chars and varies', () {
    final a = LocalServerSetup.generateToken();
    expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(a, isNot(LocalServerSetup.generateToken()));
  });

  test('unit file has hardening and port', () {
    final u = LocalServerSetup.unitFile(9000);
    for (final s in [
      'User=eatpoint',
      'Restart=on-failure',
      'NoNewPrivileges=true',
      'ProtectSystem=strict',
      'ReadWritePaths=/var/lib/eatpoint',
      'PrivateTmp=true',
      '--port 9000',
      '--token-file /etc/eatpoint/token',
    ]) {
      expect(u, contains(s));
    }
  });

  test('full install with password sudo', () async {
    final shell = FakeShell();
    final steps = <LocalServerSetupStep>[];
    final r = await _setup(shell).install(_creds, onStep: steps.add);

    expect(r.baseUrl.toString(), 'http://192.168.1.50:8787');
    expect(r.token, 'f' * 64);
    expect(steps, [
      LocalServerSetupStep.connecting,
      LocalServerSetupStep.checkingSystem,
      LocalServerSetupStep.uploading,
      LocalServerSetupStep.configuring,
      LocalServerSetupStep.starting,
      LocalServerSetupStep.verifying,
      LocalServerSetupStep.done,
    ]);
    expect(shell.closed, isTrue);

    for (final c in shell.calls) {
      expect(c.command, isNot(contains('p4ss')));
      expect(c.command, isNot(contains('f' * 64)), reason: 'token in cmd');
      if (c.command.startsWith('sudo ') && c.command != 'sudo -n true') {
        expect(c.command, startsWith("sudo -S -p '' -k sh -c"));
      }
    }
    // Sudo commands carrying stdin: password first line, then payload.
    final upload = shell.calls.firstWhere(
      (c) => c.command.contains('tee /opt/eatpoint'),
    );
    expect(upload.stdin, "p4ss w0rd's\n# fake script\n");
    final tok = shell.calls.firstWhere(
      (c) => c.command.contains('/etc/eatpoint/token'),
    );
    expect(tok.stdin, "p4ss w0rd's\n${'f' * 64}\n");
    expect(tok.command, contains('chmod 600'));
    expect(tok.command, contains('chown eatpoint'));
    final unit = shell.calls.firstWhere(
      (c) => c.command.contains('.service >'),
    );
    expect(unit.stdin, "p4ss w0rd's\n${LocalServerSetup.unitFile(8787)}");

    final all = shell.calls.map((c) => c.command).join('\n');
    expect(all, contains('useradd --system --no-create-home'));
    expect(all, contains('/var/lib/eatpoint'));
    expect(all, contains('systemctl daemon-reload'));
    expect(all, contains('systemctl enable --now eatpoint-sync'));
    expect(all, isNot(contains('ufw allow')));
    expect(all, isNot(contains('apt-get install')));
    expect(shell.calls.last.command, contains('curl -fsS'));
  });

  test('installs python when missing, ufw only when active', () async {
    final shell = FakeShell()
      ..pythonPresent = false
      ..ufwActive = true;
    final steps = <LocalServerSetupStep>[];
    await _setup(shell).install(_creds, servicePort: 9001, onStep: steps.add);
    final all = shell.calls.map((c) => c.command).join('\n');
    expect(all, contains('apt-get install -y python3'));
    expect(all, contains('ufw allow 9001/tcp'));
    expect(steps, contains(LocalServerSetupStep.installingPython));
  });

  test('root login uses no sudo and passwordless sudo uses -n', () async {
    final root = FakeShell()..root = true;
    await _setup(root).install(
      const LocalServerCredentials(host: 'h', user: 'root', password: 'x'),
    );
    expect(root.calls.any((c) => c.command.contains('sudo')), isFalse);
    expect(root.calls.every((c) => !(c.stdin ?? '').startsWith('x\n')), isTrue);

    final np = FakeShell()..nopass = true;
    await _setup(np).install(_creds);
    expect(np.calls.any((c) => c.command.startsWith('sudo -n sh -c')), isTrue);
    expect(np.calls.any((c) => c.command.contains('sudo -S')), isFalse);
  });

  test('warns on non-Ubuntu but continues', () async {
    final shell = FakeShell()..os = 'fedora\n';
    final r = await _setup(shell).install(_creds);
    expect(r.warnings, isNotEmpty);
  });

  test('failed health check throws at verifying', () async {
    final shell = FakeShell()..healthOk = false;
    await expectLater(
      _setup(shell).install(_creds),
      throwsA(
        isA<LocalServerSetupException>().having(
          (e) => e.step,
          'step',
          LocalServerSetupStep.verifying,
        ),
      ),
    );
    expect(shell.closed, isTrue);
  });

  test('connect auth failure maps to authFailed', () async {
    final s = LocalServerSetup(
      connector: (_) async => throw SSHAuthFailError('all methods failed'),
    );
    await expectLater(
      s.install(_creds),
      throwsA(
        isA<LocalServerSetupException>()
            .having((e) => e.step, 'step', LocalServerSetupStep.connecting)
            .having((e) => e.authFailed, 'authFailed', true),
      ),
    );
  });

  test('uninstall keeps data unless asked', () async {
    final keep = FakeShell();
    await _setup(keep).uninstall(_creds);
    final k = keep.calls.map((c) => c.command).join('\n');
    expect(k, contains('systemctl disable --now eatpoint-sync'));
    expect(k, isNot(contains('rm -rf /var/lib/eatpoint')));

    final del = FakeShell();
    await _setup(del).uninstall(_creds, deleteData: true);
    expect(
      del.calls.map((c) => c.command).join('\n'),
      contains('rm -rf /var/lib/eatpoint'),
    );
  });
}
