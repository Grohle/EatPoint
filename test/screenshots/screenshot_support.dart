import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Renders real app screens to PNG files, for the README and for previews.
///
/// Off by default so `flutter test` never writes files. Run with:
///
///   flutter test test/screenshots --dart-define=SCREENSHOTS=true \
///     --dart-define=SCREENSHOT_DIR=build/screenshots
///
/// Text uses the app's own fonts (Poppins, the icon fonts) instead of the
/// test font, so the captures look like the app on a phone.
const bool screenshotsEnabled = bool.fromEnvironment('SCREENSHOTS');
const String screenshotDir = String.fromEnvironment(
  'SCREENSHOT_DIR',
  defaultValue: 'build/screenshots',
);

/// The languages to capture, e.g. `--dart-define=SCREENSHOT_LOCALES=de,fr`.
const String _screenshotLocales = String.fromEnvironment(
  'SCREENSHOT_LOCALES',
  defaultValue: 'en,es',
);
final List<Locale> screenshotLocales = [
  for (final code in _screenshotLocales.split(','))
    if (code.trim().isNotEmpty) Locale(code.trim()),
];

/// A phone of 412 x 915 logical pixels, 1080 x 2400 physical.
const phoneSize = Size(412, 915);
const phonePixelRatio = 2.625;

final _boundaryKey = GlobalKey();
bool _fontsLoaded = false;

Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  final poppins = Directory('fonts')
      .listSync()
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.contains('Poppins-') && p.endsWith('.ttf'))
      .toList();
  await family('Poppins', poppins);
  await family('CustomIcons', ['fonts/CustomIcons.ttf']);
  await family('Nunito', ['fonts/Nunito.ttf']);
  final sdk = _flutterRoot();
  final materialFonts = '$sdk/bin/cache/artifacts/material_fonts';
  await family('MaterialIcons', ['$materialFonts/MaterialIcons-Regular.otf']);
  final roboto = Directory(materialFonts)
      .listSync()
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.contains('Roboto-') && p.endsWith('.ttf'))
      .toList();
  await family('Roboto', roboto);
}

String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // flutter_tester runs from <flutter>/bin/cache/artifacts/engine/<platform>.
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    if (Directory(
      '${dir.path}/bin/cache/artifacts/material_fonts',
    ).existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return '/opt/sdk/flutter';
}

/// Sizes the test view like a phone.
void usePhone(WidgetTester tester, {Size size = phoneSize}) {
  tester.view.physicalSize = size * phonePixelRatio;
  tester.view.devicePixelRatio = phonePixelRatio;
  addTearDown(tester.view.reset);
}

/// Wraps [child] in the app's theme and localizations, inside the boundary
/// [capture] reads.
Widget screenshotApp({
  required Widget home,
  bool dark = false,
  Locale locale = const Locale('en'),
  Map<String, WidgetBuilder> routes = const {},
}) {
  return RepaintBoundary(
    key: _boundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(AppPalette.light),
      darkTheme: buildAppTheme(AppPalette.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: home,
      routes: routes,
    ),
  );
}

/// Lets images and SVGs finish loading, then settles frames.
Future<void> settleAssets(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }
}

/// Writes what is on screen to `<screenshotDir>/<name>.png`.
Future<File> capture(
  WidgetTester tester,
  String name, {
  double pixelRatio = phonePixelRatio,
}) async {
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final file = File('$screenshotDir/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!);
  return file;
}
