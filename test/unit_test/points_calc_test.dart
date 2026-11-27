import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';

void main() {
  group('PointsCalc', () {
    test('pointsPer100g divides kcal by 100', () {
      expect(PointsCalc.pointsPer100g(133), closeTo(1.33, 1e-9));
    });

    test('pointsPer100g is 0 for zero or negative kcal', () {
      expect(PointsCalc.pointsPer100g(0), 0);
      expect(PointsCalc.pointsPer100g(-50), 0);
    });

    test('gramsPerPoint', () {
      expect(PointsCalc.gramsPerPoint(400 / 300), closeTo(75, 1e-9));
      expect(PointsCalc.gramsPerPoint(1.33333), closeTo(75, 0.01));
    });

    test('gramsPerPoint is null without energy', () {
      expect(PointsCalc.gramsPerPoint(0), isNull);
      expect(PointsCalc.gramsPerPoint(-1), isNull);
    });

    test('gramsToPoints rounds to two decimals', () {
      // 190 * (4/3) / 100 = 2.5333.. -> 2.53
      expect(PointsCalc.gramsToPoints(190, 4 / 3), 2.53);
    });

    test('gramsToPoints is 0 for no grams or no energy', () {
      expect(PointsCalc.gramsToPoints(0, 4 / 3), 0);
      expect(PointsCalc.gramsToPoints(-5, 4 / 3), 0);
      expect(PointsCalc.gramsToPoints(100, 0), 0);
    });

    group('pointsToGrams', () {
      test('2.5 points of a food with 4/3 points per 100 g', () {
        final r = PointsCalc.pointsToGrams(2.5, 4 / 3);
        expect(r.exactGrams, closeTo(187.5, 1e-9));
        // Above 150 g rounds to 10 g: 18.75 -> 19 -> 190.
        expect(r.roundedGrams, 190);
        expect(r.realPoints, 2.53);
      });

      test('1.5 points of a food with 4 points per 100 g', () {
        final r = PointsCalc.pointsToGrams(1.5, 4);
        expect(r.exactGrams, closeTo(37.5, 1e-9));
        // 30-150 g rounds to 5 g: 7.5 rounds half up to 8 -> 40.
        expect(r.roundedGrams, 40);
        expect(r.realPoints, closeTo(1.6, 1e-9));
      });

      test('oil with 12 g per point', () {
        final r = PointsCalc.pointsToGrams(0.25, 100 / 12);
        expect(r.exactGrams, closeTo(3.0, 1e-9));
        expect(r.roundedGrams, 3);
        expect(r.realPoints, closeTo(0.25, 1e-9));
      });

      test('non-positive inputs give zeros', () {
        for (final r in [
          PointsCalc.pointsToGrams(0, 4),
          PointsCalc.pointsToGrams(-1, 4),
          PointsCalc.pointsToGrams(1, 0),
          PointsCalc.pointsToGrams(1, -4),
        ]) {
          expect(r.exactGrams, 0);
          expect(r.roundedGrams, 0);
          expect(r.realPoints, 0);
        }
      });
    });

    test('roundPracticalGrams boundaries', () {
      expect(PointsCalc.roundPracticalGrams(29.4), 29);
      expect(PointsCalc.roundPracticalGrams(29.6), 30);
      expect(PointsCalc.roundPracticalGrams(30), 30);
      expect(PointsCalc.roundPracticalGrams(32), 30);
      expect(PointsCalc.roundPracticalGrams(33), 35);
      expect(PointsCalc.roundPracticalGrams(150), 150);
      expect(PointsCalc.roundPracticalGrams(152), 150);
      expect(PointsCalc.roundPracticalGrams(156), 160);
    });

    test('roundPracticalGrams never gives 0 for a positive amount', () {
      expect(PointsCalc.roundPracticalGrams(0.3), 1);
      expect(PointsCalc.roundPracticalGrams(0), 0);
    });

    test('roundPracticalPieces rounds to halves', () {
      expect(PointsCalc.roundPracticalPieces(1.2), 1.0);
      expect(PointsCalc.roundPracticalPieces(1.3), 1.5);
      expect(PointsCalc.roundPracticalPieces(0.1), 0.5);
      expect(PointsCalc.roundPracticalPieces(0), 0);
    });

    test('snapToStep rounds to quarter points by default', () {
      expect(PointsCalc.snapToStep(9.78), closeTo(9.75, 1e-9));
      expect(PointsCalc.snapToStep(5.27), closeTo(5.25, 1e-9));
      // 5.13 / 0.25 = 20.52 -> 21 -> 5.25
      expect(PointsCalc.snapToStep(5.13), closeTo(5.25, 1e-9));
      expect(PointsCalc.snapToStep(0.12), closeTo(0.0, 1e-9));
    });

    test('snapToStep with a custom step', () {
      // 1.3 / 0.5 = 2.6 -> 3 -> 1.5
      expect(PointsCalc.snapToStep(1.3, step: 0.5), closeTo(1.5, 1e-9));
      // 1.2 / 0.5 = 2.4 -> 2 -> 1.0
      expect(PointsCalc.snapToStep(1.2, step: 0.5), closeTo(1.0, 1e-9));
    });

    group('profileFromMacros', () {
      test('splits energy by macro', () {
        // carbs 41 * 4 = 164, protein 9.6 * 4 = 38.4, fat 3.4 * 9 = 30.6,
        // total 233 kcal.
        final p = PointsCalc.profileFromMacros(
          carbs: 41,
          protein: 9.6,
          fat: 3.4,
        )!;
        expect(p.carbShare, closeTo(164 / 233, 0.001));
        expect(p.proteinShare, closeTo(38.4 / 233, 0.001));
        expect(p.fatShare, closeTo(30.6 / 233, 0.001));
        expect(p.carbShare, closeTo(0.7039, 0.001));
        expect(p.proteinShare, closeTo(0.1648, 0.001));
        expect(p.fatShare, closeTo(0.1313, 0.001));
        expect(p.total, closeTo(1.0, 1e-9));
      });

      test('all zero gives null', () {
        expect(
          PointsCalc.profileFromMacros(carbs: 0, protein: 0, fat: 0),
          isNull,
        );
      });

      test('negative inputs are treated as 0', () {
        final p = PointsCalc.profileFromMacros(
          carbs: -10,
          protein: 5,
          fat: -2,
        )!;
        expect(p.carbShare, 0);
        expect(p.proteinShare, closeTo(1.0, 1e-9));
        expect(p.fatShare, 0);
        expect(
          PointsCalc.profileFromMacros(carbs: -1, protein: -1, fat: -1),
          isNull,
        );
      });
    });

    group('nearestStandardProfile', () {
      test('typical mixed food maps to 50/25/25', () {
        final p = PointsCalc.profileFromMacros(
          carbs: 41,
          protein: 9.6,
          fat: 3.4,
        )!;
        expect(
          PointsCalc.nearestStandardProfile(p),
          const PointsProfile(
            carbShare: 0.5,
            proteinShare: 0.25,
            fatShare: 0.25,
          ),
        );
      });

      test('pure carbs maps to carbsOnly', () {
        expect(
          PointsCalc.nearestStandardProfile(
            const PointsProfile(carbShare: 1, proteinShare: 0, fatShare: 0),
          ),
          PointsProfile.carbsOnly,
        );
      });

      test('protein and fat food maps to 0/50/50', () {
        expect(
          PointsCalc.nearestStandardProfile(
            const PointsProfile(
              carbShare: 0.05,
              proteinShare: 0.48,
              fatShare: 0.47,
            ),
          ),
          const PointsProfile(carbShare: 0, proteinShare: 0.5, fatShare: 0.5),
        );
      });
    });

    test('there are nine standard profiles that each sum to 1', () {
      expect(PointsCalc.standardProfiles.length, 9);
      for (final p in PointsCalc.standardProfiles) {
        expect(p.total, closeTo(1.0, 1e-9));
      }
    });

    test('split divides points by profile', () {
      final result = PointsCalc.split(
        1.5,
        const PointsProfile(carbShare: 0, proteinShare: 0.5, fatShare: 0.5),
      );
      expect(
        result,
        const MacroPoints(carbs: 0, protein: 0.75, fat: 0.75),
      );
    });
  });

  group('MacroPoints', () {
    const a = MacroPoints(carbs: 1, protein: 2, fat: 3);
    const b = MacroPoints(carbs: 0.5, protein: 0.25, fat: 1);

    test('total', () {
      expect(a.total, closeTo(6, 1e-9));
      expect(MacroPoints.zero.total, 0);
    });

    test('addition', () {
      expect(a + b, const MacroPoints(carbs: 1.5, protein: 2.25, fat: 4));
    });

    test('subtraction', () {
      expect(a - b, const MacroPoints(carbs: 0.5, protein: 1.75, fat: 2));
    });

    test('multiplication by a factor', () {
      expect(a * 2, const MacroPoints(carbs: 2, protein: 4, fat: 6));
      expect(a * 0.5, const MacroPoints(carbs: 0.5, protein: 1, fat: 1.5));
    });
  });
}
