import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/label_scan/domain/label_row_builder.dart';
import 'package:opennutritracker/features/label_scan/domain/nutrition_label_parser.dart';

void main() {
  test('column-by-column lines are regrouped into rows', () {
    final lines = [
      // Labels first (left column), then values (right column).
      const OcrLine('Grasas', 0, 100, 100, 120),
      const OcrLine('Hidratos de carbono', 0, 140, 100, 160),
      const OcrLine('Proteínas', 0, 180, 100, 200),
      const OcrLine('3,4 g', 200, 100, 260, 120),
      const OcrLine('41 g', 200, 140, 260, 160),
      const OcrLine('9,6 g', 200, 180, 260, 200),
    ];
    expect(LabelRowBuilder.rows(lines), [
      'Grasas 3,4 g',
      'Hidratos de carbono 41 g',
      'Proteínas 9,6 g',
    ]);
  });

  test('rows come out top to bottom regardless of input order', () {
    final lines = [
      const OcrLine('Proteínas 9,6 g', 0, 180, 260, 200),
      const OcrLine('Grasas 3,4 g', 0, 100, 260, 120),
      const OcrLine('Sal 1,1 g', 0, 220, 260, 240),
    ];
    expect(LabelRowBuilder.rows(lines), [
      'Grasas 3,4 g',
      'Proteínas 9,6 g',
      'Sal 1,1 g',
    ]);
  });

  test('cells in a row are ordered left to right', () {
    final lines = [
      const OcrLine('3,4 g', 200, 100, 260, 120),
      const OcrLine('Grasas', 0, 100, 100, 120),
    ];
    expect(LabelRowBuilder.rows(lines), ['Grasas 3,4 g']);
  });

  test('slightly skewed rows still group', () {
    final lines = [
      const OcrLine('Grasas', 0, 100, 100, 120),
      // Centre 6 px lower; half the line height is 10.
      const OcrLine('3,4 g', 200, 106, 260, 126),
    ];
    expect(LabelRowBuilder.rows(lines), ['Grasas 3,4 g']);
  });

  test('a skew above half the line height starts a new row', () {
    final lines = [
      const OcrLine('Grasas', 0, 100, 100, 120),
      const OcrLine('3,4 g', 200, 115, 260, 135),
    ];
    expect(LabelRowBuilder.rows(lines), ['Grasas', '3,4 g']);
  });

  test('empty and whitespace-only texts are ignored', () {
    final lines = [
      const OcrLine('', 0, 100, 100, 120),
      const OcrLine('   ', 100, 100, 150, 120),
      const OcrLine('Grasas', 0, 100, 100, 120),
    ];
    expect(LabelRowBuilder.rows(lines), ['Grasas']);
    expect(LabelRowBuilder.rows([]), isEmpty);
  });

  test('texts are trimmed', () {
    expect(LabelRowBuilder.rows([const OcrLine('  Sal  ', 0, 0, 50, 20)]), [
      'Sal',
    ]);
  });

  test('zero-height boxes fall back to a 10 px band', () {
    final lines = [
      const OcrLine('Sal', 0, 100, 50, 100),
      const OcrLine('1,1 g', 100, 103, 150, 103),
    ];
    expect(LabelRowBuilder.rows(lines), ['Sal 1,1 g']);
  });

  test('rebuilt rows parse into values', () {
    final lines = [
      const OcrLine('Valor energético', 0, 10, 150, 30),
      const OcrLine('Grasas', 0, 50, 150, 70),
      const OcrLine('Hidratos de carbono', 0, 90, 150, 110),
      const OcrLine('Proteínas', 0, 130, 150, 150),
      const OcrLine('1035 kJ / 247 kcal', 200, 10, 360, 30),
      const OcrLine('3,4 g', 200, 52, 260, 72),
      const OcrLine('41 g', 200, 88, 260, 108),
      const OcrLine('9,6 g', 200, 131, 260, 151),
    ];
    final v = NutritionLabelParser.parse(LabelRowBuilder.rows(lines));
    expect(v.kcal, 247);
    expect(v.fat, 3.4);
    expect(v.carbs, 41);
    expect(v.protein, 9.6);
  });
}
