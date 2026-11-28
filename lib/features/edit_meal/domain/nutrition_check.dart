/// EatPoint: whether a food's energy matches its macronutrients, and what
/// to point out when it doesn't.
///
/// Energy is expected to be about 4 kcal per gram of carbohydrate and of
/// protein and 9 per gram of fat (Atwater). European labels also count 2
/// kcal per gram of fibre, so when fibre is given either sum is accepted.
class NutritionCheck {
  /// How far apart the two may be, as a share of the larger one.
  static const tolerance = 0.05;

  /// Below this many kcal apart, rounding on the label explains it.
  static const slack = 5.0;

  final double enteredKcal;

  /// What the macronutrients add up to (with fibre, when that is closer).
  final double expectedKcal;
  final double carbsKcal;
  final double proteinKcal;
  final double fatKcal;

  /// Whether the energy looks entered in kJ rather than kcal.
  final bool looksLikeKj;

  const NutritionCheck._({
    required this.enteredKcal,
    required this.expectedKcal,
    required this.carbsKcal,
    required this.proteinKcal,
    required this.fatKcal,
    required this.looksLikeKj,
  });

  /// Null when the values add up, or when there is too little to check.
  static NutritionCheck? of({
    required double? kcal,
    required double? carbs,
    required double? protein,
    required double? fat,
    double? fibre,
  }) {
    if (kcal == null || carbs == null || protein == null || fat == null) {
      return null;
    }
    final c = carbs * 4, p = protein * 4, f = fat * 9;
    final plain = c + p + f;
    final withFibre = plain + 2 * (fibre ?? 0);
    bool fits(double expected) {
      final delta = (kcal - expected).abs();
      final ceiling = kcal.abs() > expected.abs() ? kcal.abs() : expected.abs();
      return ceiling <= 0 || delta <= slack || delta <= tolerance * ceiling;
    }

    if (fits(plain) || fits(withFibre)) return null;
    final expected = (kcal - withFibre).abs() < (kcal - plain).abs()
        ? withFibre
        : plain;
    return NutritionCheck._(
      enteredKcal: kcal,
      expectedKcal: expected,
      carbsKcal: c,
      proteinKcal: p,
      fatKcal: f,
      looksLikeKj: expected > 0 && (kcal / expected - 4.184).abs() < 0.4,
    );
  }
}
