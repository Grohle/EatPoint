import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/splash_screen.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  Widget app({required bool userInitialized, required List<String> routes}) {
    return MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      home: SplashScreen(userInitialized: userInitialized),
      onGenerateRoute: (settings) {
        routes.add(settings.name ?? '');
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('next')),
        );
      },
    );
  }

  testWidgets('shows the wordmark and routes to onboarding on first run', (
    tester,
  ) async {
    final routes = <String>[];
    await tester.pumpWidget(app(userInitialized: false, routes: routes));
    await tester.pump(const Duration(milliseconds: 100));
    expect(routes, isEmpty);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('EatPoint'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(routes, contains(NavigationOptions.onboardingRoute));
  });

  testWidgets('routes to the main screen for a returning user', (tester) async {
    final routes = <String>[];
    await tester.pumpWidget(app(userInitialized: true, routes: routes));
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pumpAndSettle();
    expect(routes, contains(NavigationOptions.mainRoute));
  });
}
