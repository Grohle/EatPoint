import 'dart:math' as math;

/// How the energy of a food splits between carbohydrate, protein and fat
/// points. The three shares always add up to 1.
class PointsProfile {
  final double carbShare;
  final double proteinShare;
  final double fatShare;

  const PointsProfile({
    required this.carbShare,
    required this.proteinShare,
    required this.fatShare,
  });

  static const carbsOnly = PointsProfile(
    carbShare: 1,
    proteinShare: 0,
    fatShare: 0,
  );
  static const proteinOnly = PointsProfile(
    carbShare: 0,
    proteinShare: 1,
    fatShare: 0,
  );
  static const fatOnly = PointsProfile(
    carbShare: 0,
    proteinShare: 0,
    fatShare: 1,
  );

  double get total => carbShare + proteinShare + fatShare;

  @override
  bool operator ==(Object other) =>
      other is PointsProfile &&
      (other.carbShare - carbShare).abs() < 1e-9 &&
      (other.proteinShare - proteinShare).abs() < 1e-9 &&
      (other.fatShare - fatShare).abs() < 1e-9;

  @override
  int get hashCode => Object.hash(
    (carbShare * 1000).round(),
    (proteinShare * 1000).round(),
    (fatShare * 1000).round(),
  );

  @override
  String toString() =>
      'PointsProfile(C $carbShare, P $proteinShare, F $fatShare)';
}

/// Points split by macronutrient.
class MacroPoints {
  final double carbs;
  final double protein;
  final double fat;

  const MacroPoints({
    required this.carbs,
    required this.protein,
    required this.fat,
  });

  static const zero = MacroPoints(carbs: 0, protein: 0, fat: 0);

  double get total => carbs + protein + fat;

  MacroPoints operator +(MacroPoints other) => MacroPoints(
    carbs: carbs + other.carbs,
    protein: protein + other.protein,
    fat: fat + other.fat,
  );

  MacroPoints operator -(MacroPoints other) => MacroPoints(
    carbs: carbs - other.carbs,
    protein: protein - other.protein,
    fat: fat - other.fat,
  );

  MacroPoints operator *(double factor) => MacroPoints(
    carbs: carbs * factor,
    protein: protein * factor,
    fat: fat * factor,
  );

  @override
  bool operator ==(Object other) =>
      other is MacroPoints &&
      (other.carbs - carbs).abs() < 1e-9 &&
      (other.protein - protein).abs() < 1e-9 &&
      (other.fat - fat).abs() < 1e-9;

  @override
  int get hashCode => Object.hash(
    (carbs * 1000).round(),
    (protein * 1000).round(),
    (fat * 1000).round(),
  );

  @override
  String toString() => 'MacroPoints(C $carbs, P $protein, F $fat)';
}

/// Result of converting a number of points into grams.
class PointsToGramsResult {
  /// Grams that give exactly the requested points.
  final double exactGrams;

  /// [exactGrams] rounded to an amount that is easy to weigh on a kitchen
  /// scale (see [PointsCalc.roundPracticalGrams]). This is the amount that
  /// gets logged.
  final double roundedGrams;

  /// The points that [roundedGrams] actually contain, to two decimals.
  final double realPoints;

  const PointsToGramsResult({
    required this.exactGrams,
    required this.roundedGrams,
    required this.realPoints,
  });

  @override
  String toString() =>
      'PointsToGramsResult(exact $exactGrams g, '
      'rounded $roundedGrams g, real $realPoints pts)';
}

/// Pure functions for the points system.
///
/// One point is 100 kcal from a single macronutrient. A food's points per
/// 100 g are its kcal per 100 g divided by 100, and its [PointsProfile]
/// says how those points split between carbohydrate, protein and fat.
class PointsCalc {
  static const kcalPerPoint = 100.0;

  /// Points are planned and shown in quarters of a point.
  static const pointStep = 0.25;

  /// Grams of fibre in one fibre point. Fibre is counted apart from the
  /// energy points: it is a minimum to reach, not a budget to stay under.
  static const fibreGramsPerPoint = 5.0;

  /// The fibre points in [fibreGrams] grams of fibre.
  static double fibrePoints(double fibreGrams) =>
      fibreGrams <= 0 ? 0 : fibreGrams / fibreGramsPerPoint;

  /// Energy densities used to split a food's energy by macronutrient.
  /// Fibre is left out of the split: its small energy contribution is not
  /// a carbohydrate the user budgets for.
  static const carbsKcalPerGram = 4.0;
  static const proteinKcalPerGram = 4.0;
  static const fatKcalPerGram = 9.0;

  /// The nine profiles used for hand-classified foods: every split where
  /// each share is a multiple of 0.25 and that occurs in practice.
  static const standardProfiles = <PointsProfile>[
    PointsProfile.carbsOnly,
    PointsProfile.proteinOnly,
    PointsProfile.fatOnly,
    PointsProfile(carbShare: 0, proteinShare: 0.5, fatShare: 0.5),
    PointsProfile(carbShare: 0.5, proteinShare: 0, fatShare: 0.5),
    PointsProfile(carbShare: 0.5, proteinShare: 0.5, fatShare: 0),
    PointsProfile(carbShare: 0.25, proteinShare: 0.25, fatShare: 0.5),
    PointsProfile(carbShare: 0.5, proteinShare: 0.25, fatShare: 0.25),
    PointsProfile(carbShare: 0.25, proteinShare: 0.5, fatShare: 0.25),
  ];

  /// Points per 100 g (or 100 ml) of a food with [kcalPer100g].
  static double pointsPer100g(double kcalPer100g) =>
      kcalPer100g <= 0 ? 0 : kcalPer100g / kcalPerPoint;

  /// Grams (or ml) of a food that make one point.
  /// Returns null when the food has no energy.
  static double? gramsPerPoint(double pointsPer100g) =>
      pointsPer100g <= 0 ? null : 100 / pointsPer100g;

  /// The exact split of a food's energy between its macronutrients, from its
  /// macros per 100 g. Returns null when all three are zero or missing.
  static PointsProfile? profileFromMacros({
    required double carbs,
    required double protein,
    required double fat,
  }) {
    final carbKcal = math.max(0.0, carbs) * carbsKcalPerGram;
    final proteinKcal = math.max(0.0, protein) * proteinKcalPerGram;
    final fatKcal = math.max(0.0, fat) * fatKcalPerGram;
    final total = carbKcal + proteinKcal + fatKcal;
    if (total <= 0) return null;
    return PointsProfile(
      carbShare: carbKcal / total,
      proteinShare: proteinKcal / total,
      fatShare: fatKcal / total,
    );
  }

  /// The standard profile closest to [profile] (smallest squared distance).
  static PointsProfile nearestStandardProfile(PointsProfile profile) {
    PointsProfile best = standardProfiles.first;
    double bestDistance = double.infinity;
    for (final candidate in standardProfiles) {
      final distance =
          math.pow(candidate.carbShare - profile.carbShare, 2) +
          math.pow(candidate.proteinShare - profile.proteinShare, 2) +
          math.pow(candidate.fatShare - profile.fatShare, 2);
      if (distance < bestDistance) {
        bestDistance = distance.toDouble();
        best = candidate;
      }
    }
    return best;
  }

  /// Points in [grams] of a food with [pointsPer100g], to two decimals.
  static double gramsToPoints(double grams, double pointsPer100g) {
    if (grams <= 0 || pointsPer100g <= 0) return 0;
    return roundTo(grams * pointsPer100g / 100, 2);
  }

  /// Grams of a food with [pointsPer100g] that give [targetPoints], both
  /// exact and rounded for weighing. Returns zeros when either input is not
  /// positive.
  static PointsToGramsResult pointsToGrams(
    double targetPoints,
    double pointsPer100g,
  ) {
    if (targetPoints <= 0 || pointsPer100g <= 0) {
      return const PointsToGramsResult(
        exactGrams: 0,
        roundedGrams: 0,
        realPoints: 0,
      );
    }
    final exact = targetPoints * 100 / pointsPer100g;
    final rounded = roundPracticalGrams(exact);
    return PointsToGramsResult(
      exactGrams: exact,
      roundedGrams: rounded,
      realPoints: gramsToPoints(rounded, pointsPer100g),
    );
  }

  /// Rounds grams to an amount that is easy to weigh:
  /// under 30 g to the nearest 1 g, from 30 g to 150 g to the nearest 5 g,
  /// above 150 g to the nearest 10 g. Never rounds a positive amount to 0.
  static double roundPracticalGrams(double grams) {
    if (grams <= 0) return 0;
    final double step;
    if (grams < 30) {
      step = 1;
    } else if (grams <= 150) {
      step = 5;
    } else {
      step = 10;
    }
    final rounded = (grams / step).round() * step;
    return rounded == 0 ? step : rounded.toDouble();
  }

  /// Rounds a count of pieces (units, slices, servings) to the nearest half.
  static double roundPracticalPieces(double pieces) {
    if (pieces <= 0) return 0;
    final rounded = (pieces * 2).round() / 2;
    return rounded == 0 ? 0.5 : rounded;
  }

  /// Rounds [points] to the nearest multiple of [step].
  static double snapToStep(double points, {double step = pointStep}) =>
      (points / step).round() * step;

  /// Splits [points] of a food by its [profile].
  static MacroPoints split(double points, PointsProfile profile) => MacroPoints(
    carbs: points * profile.carbShare,
    protein: points * profile.proteinShare,
    fat: points * profile.fatShare,
  );

  /// Rounds [value] to [decimals] decimal places.
  static double roundTo(double value, int decimals) {
    final factor = math.pow(10, decimals).toDouble();
    return (value * factor).round() / factor;
  }
}
