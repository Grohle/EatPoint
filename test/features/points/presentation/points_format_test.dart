import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/points/presentation/points_format.dart';

void main() {
  final en = PointsFormat.forLocale('en');
  final es = PointsFormat.forLocale('es');

  group('PointsFormat.points', () {
    test('uses the locale decimal separator', () {
      expect(en.points(2.5), '2.5');
      expect(es.points(2.5), '2,5');
    });

    test('keeps at most two decimals and drops trailing zeros', () {
      expect(en.points(2.5299999), '2.53');
      expect(en.points(3), '3');
      expect(en.points(1.3333), '1.33');
      expect(es.points(2.53), '2,53');
    });

    test('never prints "-0"', () {
      expect(en.points(-0.0), '0');
      expect(en.points(-0.001), '0');
      expect(en.points(0), '0');
      expect(es.points(-0.004), '0');
    });
  });

  group('PointsFormat.grams', () {
    test('keeps one decimal', () {
      expect(en.grams(187.5), '187.5');
      expect(es.grams(187.5), '187,5');
      expect(en.grams(190), '190');
    });

    test('never prints "-0"', () {
      expect(en.grams(-0.0), '0');
    });
  });

  group('PointsFormat.parse', () {
    test('accepts both decimal separators', () {
      expect(PointsFormat.parse('2.5'), 2.5);
      expect(PointsFormat.parse('2,5'), 2.5);
      expect(PointsFormat.parse(' 0,25 '), 0.25);
    });

    test('returns null for empty or non-numeric text', () {
      expect(PointsFormat.parse(''), isNull);
      expect(PointsFormat.parse('   '), isNull);
      expect(PointsFormat.parse('abc'), isNull);
    });
  });
}
