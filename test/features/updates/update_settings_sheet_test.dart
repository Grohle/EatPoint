import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/updates/data/update_checker.dart';
import 'package:opennutritracker/features/updates/data/update_store.dart';
import 'package:opennutritracker/features/updates/presentation/update_prompt.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/points/points_test_support.dart';
import '../../helpers/fake_hive_db_provider.dart';

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  home: Scaffold(body: home),
);

UpdateChecker _checker(List<String> tags) => UpdateChecker(
  MockClient(
    (_) async => http.Response(
      jsonEncode([
        for (final tag in tags)
          {
            'tag_name': tag,
            'html_url': 'https://example.org/$tag',
            'body': '## What\'s new\n- **Faster** sync',
            'assets': <Object>[],
          },
      ]),
      200,
    ),
  ),
);

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'EatPoint',
      packageName: 'io.github.grohle.eatpoint',
      version: '0.3.2',
      buildNumber: '6',
      buildSignature: '',
    );
  });

  UpdateStore store() =>
      UpdateStore(FakeHiveDBProvider(pointsSettingsBox: MemoryStringBox()));

  testWidgets('shows the version, the switch and "up to date"', (tester) async {
    final updates = store();
    await tester.pumpWidget(
      _app(UpdateSettingsSheet(store: updates, checker: _checker(['v0.3.2']))),
    );
    await tester.pumpAndSettle();
    final s = S.of(tester.element(find.byType(UpdateSettingsSheet)));
    expect(find.text(s.updateInstalledVersion('0.3.2')), findsOneWidget);

    await tester.tap(find.text(s.updateAutoCheck));
    await tester.pumpAndSettle();
    expect(updates.autoCheck, isFalse);

    await tester.tap(find.text(s.updateCheckNow));
    await tester.pumpAndSettle();
    expect(find.text(s.updateUpToDate), findsOneWidget);
  });

  testWidgets('a newer release opens the update dialog with its news', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(UpdateSettingsSheet(store: store(), checker: _checker(['v0.4.0']))),
    );
    await tester.pumpAndSettle();
    final s = S.of(tester.element(find.byType(UpdateSettingsSheet)));
    await tester.tap(find.text(s.updateCheckNow));
    await tester.pumpAndSettle();
    expect(find.text(s.updateAvailableTitle('0.4.0')), findsOneWidget);
    expect(find.text('• Faster sync'), findsOneWidget);
    expect(find.text(s.updateDownload), findsOneWidget);
  });
}
