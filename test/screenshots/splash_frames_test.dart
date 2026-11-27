import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/splash_screen.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';

import 'screenshot_support.dart';

/// Frames of the launch animation, light and dark.
void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'splash animation frames (${dark ? 'dark' : 'light'})',
      (tester) async {
        await loadAppFonts();
        usePhone(tester);
        await tester.pumpWidget(
          screenshotApp(
            dark: dark,
            home: const SplashScreen(userInitialized: true),
            routes: {
              NavigationOptions.mainRoute: (_) => const Scaffold(),
              NavigationOptions.onboardingRoute: (_) => const Scaffold(),
            },
          ),
        );
        await settleAssets(tester);
        var elapsed = 0;
        // Milliseconds after launch at which to capture.
        for (final at in [0, 250, 450, 650, 850, 1050, 1300, 1700]) {
          await tester.pump(Duration(milliseconds: at - elapsed));
          elapsed = at;
          await settleAssets(tester);
          await capture(
            tester,
            'splash/${dark ? 'dark' : 'light'}_${at.toString().padLeft(4, '0')}',
            pixelRatio: 1.5,
          );
        }
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
      },
      skip: !screenshotsEnabled,
    );
  }
}
