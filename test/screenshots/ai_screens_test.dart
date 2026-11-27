import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/ai_assist_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

import 'screenshot_support.dart';

/// Captures of the AI assistant dialog, including the Gemini shortcut.
void main() {
  for (final locale in screenshotLocales) {
    final tag = locale.languageCode;

    testWidgets('ai assistant dialog ($tag)', (tester) async {
      await loadAppFonts();
      usePhone(tester);
      final storage = AiCredentialStorage(_MemoryStorage());
      await storage.setTermsAccepted(true);
      await tester.pumpWidget(
        screenshotApp(
          locale: locale,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => AiAssistDialog.show(context, storage),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await capture(tester, '$tag/ai_assist_dialog');

      final s = S.of(tester.element(find.byType(AiAssistDialog)));
      await tester.tap(find.text(s.aiAssistGeminiShortcut));
      await tester.pumpAndSettle();
      await capture(tester, '$tag/ai_assist_gemini');
    }, skip: !screenshotsEnabled);
  }
}

class _MemoryStorage implements FlutterSecureStorage {
  final store = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => store.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
