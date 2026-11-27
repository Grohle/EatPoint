import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/features/label_scan/data/label_text_reader.dart';
import 'package:opennutritracker/features/label_scan/data/remote_nutrition_extractor.dart';
import 'package:opennutritracker/features/label_scan/domain/nutrition_label_parser.dart';
import 'package:opennutritracker/features/label_scan/presentation/label_scan_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/test_l10n.dart';
import 'label_scan_test_support.dart';

class _FakeReader implements LabelTextReader {
  final List<String> rows;
  bool closed = false;
  _FakeReader(this.rows);

  @override
  Future<List<String>> readRows(String imagePath) async => rows;

  @override
  Future<void> close() async => closed = true;
}

class _ThrowingReader implements LabelTextReader {
  @override
  Future<List<String>> readRows(String imagePath) async =>
      throw StateError('ocr failed');

  @override
  Future<void> close() async {}
}

class _UnusedCredentials implements AiCredentialStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('storage is not used');
}

/// Never used for a request: the screen only calls it on Retry with AI.
RemoteNutritionExtractor _unusedExtractor() => RemoteNutritionExtractor(
  MockClient((_) async => http.Response('', 500)),
  _UnusedCredentials(),
);

const _spanishRows = [
  'Información nutricional por 100 g',
  'Valor energético 1035 kJ / 247 kcal',
  'Grasas 3,4 g',
  'de las cuales saturadas 0,6 g',
  'Hidratos de carbono 41 g',
  'de los cuales azúcares 4,1 g',
  'Fibra alimentaria 6,8 g',
  'Proteínas 9,6 g',
  'Sal 1,1 g',
];

void main() {
  late Directory dir;
  late String photo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('label_screen');
    photo = '${dir.path}/label.png';
    File(photo).writeAsBytesSync(tinyPng);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Finder field(String name) => find.descendant(
    of: find.byWidgetPredicate(
      (w) =>
          w is Semantics && w.properties.identifier == 'label-scan-field-$name',
    ),
    matching: find.byType(TextField),
  );

  String textOf(WidgetTester tester, String name) =>
      tester.widget<TextField>(field(name)).controller!.text;

  String labelOf(WidgetTester tester, String name) =>
      tester.widget<TextField>(field(name)).decoration!.labelText!;

  /// Pushes the screen from a parent so the popped result can be awaited.
  Future<void> pumpScreen(
    WidgetTester tester,
    LabelTextReader reader,
    void Function(Future<NutritionLabelValues?>) onPush,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => onPush(
                  Navigator.of(context).push<NutritionLabelValues>(
                    MaterialPageRoute(
                      builder: (_) => LabelScanScreen(
                        imagePath: photo,
                        reader: reader,
                        extractor: _unusedExtractor(),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('fills the fields and shows the success banner', (tester) async {
    final reader = _FakeReader(_spanishRows);
    await pumpScreen(tester, reader, (_) {});

    expect(textOf(tester, 'kcal'), '247');
    expect(textOf(tester, 'fat'), '3.4');
    expect(textOf(tester, 'saturatedFat'), '0.6');
    expect(textOf(tester, 'carbs'), '41');
    expect(textOf(tester, 'sugars'), '4.1');
    expect(textOf(tester, 'fiber'), '6.8');
    expect(textOf(tester, 'protein'), '9.6');
    expect(textOf(tester, 'salt'), '1.1');
    expect(find.textContaining('Adds up:'), findsOneWidget);
    expect(find.textContaining("Doesn't add up"), findsNothing);
    expect(labelOf(tester, 'carbs'), isNot(contains('check')));
  });

  testWidgets('misread carbs show the mismatch banner and a check hint', (
    tester,
  ) async {
    final rows = [..._spanishRows]..[4] = 'Hidratos de carbono 4,l g';
    rows.removeAt(5); // sugars would exceed the misread carbs
    await pumpScreen(tester, _FakeReader(rows), (_) {});

    expect(textOf(tester, 'carbs'), '4.1');
    expect(find.textContaining("Doesn't add up"), findsOneWidget);
    expect(find.textContaining('Adds up:'), findsNothing);
    expect(labelOf(tester, 'carbs'), contains('check'));
  });

  testWidgets('editing carbs to 41 flips to the success banner', (
    tester,
  ) async {
    final rows = [..._spanishRows]..[4] = 'Hidratos de carbono 4,l g';
    rows.removeAt(5);
    await pumpScreen(tester, _FakeReader(rows), (_) {});
    expect(find.textContaining("Doesn't add up"), findsOneWidget);

    await tester.enterText(field('carbs'), '41');
    await tester.pump();

    expect(find.textContaining('Adds up:'), findsOneWidget);
    expect(find.textContaining("Doesn't add up"), findsNothing);
    expect(labelOf(tester, 'carbs'), isNot(contains('check')));
  });

  testWidgets('Use these values pops the route with the values', (
    tester,
  ) async {
    late Future<NutritionLabelValues?> result;
    await pumpScreen(tester, _FakeReader(_spanishRows), (f) => result = f);

    NutritionLabelValues? popped;
    var done = false;
    result.then((v) {
      popped = v;
      done = true;
    });

    await tester.tap(find.text('Use these values'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(done, isTrue);
    expect(popped, isNotNull);
    expect(popped!.kcal, 247);
    expect(popped!.fat, 3.4);
    expect(popped!.saturatedFat, 0.6);
    expect(popped!.carbs, 41);
    expect(popped!.sugars, 4.1);
    expect(popped!.fiber, 6.8);
    expect(popped!.protein, 9.6);
    expect(popped!.salt, 1.1);
    expect(popped!.perMl, isFalse);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('edited values are what gets returned', (tester) async {
    late Future<NutritionLabelValues?> result;
    await pumpScreen(tester, _FakeReader(_spanishRows), (f) => result = f);
    NutritionLabelValues? popped;
    result.then((v) => popped = v);

    await tester.enterText(field('salt'), '2,5');
    await tester.pump();
    await tester.tap(find.text('Use these values'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(popped!.salt, 2.5);
  });

  testWidgets('an OCR failure leaves empty fields and the incomplete banner', (
    tester,
  ) async {
    await pumpScreen(tester, _ThrowingReader(), (_) {});

    expect(textOf(tester, 'kcal'), '');
    expect(textOf(tester, 'carbs'), '');
    expect(find.textContaining('Adds up:'), findsNothing);
    expect(find.textContaining("Doesn't add up"), findsNothing);
    expect(labelOf(tester, 'kcal'), contains('check'));
  });

  testWidgets('per 100 ml label switches the heading', (tester) async {
    await pumpScreen(
      tester,
      _FakeReader([
        'Por 100 ml',
        'Valor energético 180 kJ / 43 kcal',
        'Grasas 1,5 g',
        'Hidratos de carbono 5 g',
        'Proteínas 3,1 g',
      ]),
      (_) {},
    );
    expect(find.text(l10nEn.labelScanPer100ml), findsOneWidget);
  });

  testWidgets('closes the reader on dispose', (tester) async {
    final reader = _FakeReader(_spanishRows);
    await pumpScreen(tester, reader, (_) {});
    await tester.pumpWidget(const SizedBox());
    expect(reader.closed, isTrue);
  });
}
