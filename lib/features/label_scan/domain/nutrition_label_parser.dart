import 'dart:math' as math;

/// Nutrition values per 100 g (or 100 ml) read from a label. Any value the
/// label did not show, or that could not be read, is null.
class NutritionLabelValues {
  final double? kcal;
  final double? fat;
  final double? saturatedFat;
  final double? carbs;
  final double? sugars;
  final double? fiber;
  final double? protein;
  final double? salt;

  /// True when the values were read from a "per 100 ml" column.
  final bool perMl;

  const NutritionLabelValues({
    this.kcal,
    this.fat,
    this.saturatedFat,
    this.carbs,
    this.sugars,
    this.fiber,
    this.protein,
    this.salt,
    this.perMl = false,
  });

  static const empty = NutritionLabelValues();

  bool get hasCoreValues =>
      kcal != null && fat != null && carbs != null && protein != null;

  int get readCount => [
    kcal,
    fat,
    saturatedFat,
    carbs,
    sugars,
    fiber,
    protein,
    salt,
  ].where((v) => v != null).length;

  NutritionLabelValues copyWith({
    double? Function()? kcal,
    double? Function()? fat,
    double? Function()? saturatedFat,
    double? Function()? carbs,
    double? Function()? sugars,
    double? Function()? fiber,
    double? Function()? protein,
    double? Function()? salt,
    bool? perMl,
  }) => NutritionLabelValues(
    kcal: kcal != null ? kcal() : this.kcal,
    fat: fat != null ? fat() : this.fat,
    saturatedFat: saturatedFat != null ? saturatedFat() : this.saturatedFat,
    carbs: carbs != null ? carbs() : this.carbs,
    sugars: sugars != null ? sugars() : this.sugars,
    fiber: fiber != null ? fiber() : this.fiber,
    protein: protein != null ? protein() : this.protein,
    salt: salt != null ? salt() : this.salt,
    perMl: perMl ?? this.perMl,
  );

  Map<String, dynamic> toJson() => {
    'kcal': kcal,
    'fat': fat,
    'saturatedFat': saturatedFat,
    'carbs': carbs,
    'sugars': sugars,
    'fiber': fiber,
    'protein': protein,
    'salt': salt,
    'perMl': perMl,
  };

  @override
  String toString() => 'NutritionLabelValues(${toJson()})';
}

/// Result of checking label energy against its macros.
class LabelEnergyCheck {
  /// Energy printed on the label.
  final double labelKcal;

  /// Energy worked out from fat, carbs, protein and fibre.
  final double computedKcal;

  /// Relative difference, |label - computed| / max(label, computed).
  final double difference;

  final bool passes;

  const LabelEnergyCheck({
    required this.labelKcal,
    required this.computedKcal,
    required this.difference,
    required this.passes,
  });
}

/// Reads per-100 g values out of OCR text from a nutrition label, in Spanish
/// or English, tolerating common OCR mistakes (O/0, l/1, comma decimals,
/// split "k J", missing spaces).
///
/// Input is the label text as rows: one string per printed row, left to
/// right (see `LabelRowBuilder` for rebuilding rows from OCR boxes). Plain
/// OCR text with one line per row also works.
class NutritionLabelParser {
  /// Accepted difference between label energy and energy from macros.
  static const energyTolerance = 0.15;

  /// Energy densities (EU Regulation 1169/2011, Annex XIV).
  static const kcalPerGramFat = 9.0;
  static const kcalPerGramCarbs = 4.0;
  static const kcalPerGramProtein = 4.0;
  static const kcalPerGramFiber = 2.0;

  static final _number = RegExp(r'(\d+(?:[.,]\d+)?)');

  // Row labels. Order matters: sub-rows (saturates, sugars) are matched
  // before their parent row so "of which sugars" is not taken as carbs.
  static final _saturated = RegExp(
    r'satur|saturad|gesättigt|satura',
    caseSensitive: false,
  );
  static final _sugars = RegExp(
    r'az[uú]car|sugar|sucre|zucker|zucch',
    caseSensitive: false,
  );
  static final _fat = RegExp(
    r'gras|fat\b|fat[^a-z]|^fat|l[ií]pid|lipides|fett',
    caseSensitive: false,
  );
  static final _carbs = RegExp(
    r'hidrat|carbohidrat|carbohydrat|carb\b|glucid|kohlenhydrat|h\.?\s*de\s*c',
    caseSensitive: false,
  );
  static final _fiber = RegExp(
    r'fibr|fiber|fibre|ballaststoff',
    caseSensitive: false,
  );
  static final _protein = RegExp(
    r'prot[eé][ií]n|prote[ií]na|eiweiß|eiweiss',
    caseSensitive: false,
  );
  static final _salt = RegExp(
    r'\bsal\b|^sal\b|salt|\bsel\b',
    caseSensitive: false,
  );
  static final _energy = RegExp(
    r'energ|valor\s*energ|calor|kcal|kj',
    caseSensitive: false,
  );
  static final _per100 = RegExp(
    r'100\s*(g|ml|gr|m1|9)\b|100\s*(g|ml)',
    caseSensitive: false,
  );
  static final _perMl = RegExp(r'100\s*(ml|m1)', caseSensitive: false);

  /// Parses [rows] of label text.
  static NutritionLabelValues parse(List<String> rows) {
    final cleaned = rows.map(_normalise).where((r) => r.isNotEmpty).toList();
    final column = _per100Column(cleaned);
    final perMl = cleaned.any((r) => _perMl.hasMatch(r));

    double? kcal, fat, sat, carbs, sugars, fiber, protein, salt;
    for (var i = 0; i < cleaned.length; i++) {
      final row = cleaned[i];
      final lower = row.toLowerCase();
      if (_energy.hasMatch(lower) || lower.contains('kcal')) {
        kcal ??=
            _readKcal(row, column) ??
            (i + 1 < cleaned.length ? _readKcal(cleaned[i + 1], column) : null);
        continue;
      }
      if (_saturated.hasMatch(lower)) {
        sat ??= _valueAt(row, column);
      } else if (_sugars.hasMatch(lower)) {
        sugars ??= _valueAt(row, column);
      } else if (_fiber.hasMatch(lower)) {
        fiber ??= _valueAt(row, column);
      } else if (_protein.hasMatch(lower)) {
        protein ??= _valueAt(row, column);
      } else if (_carbs.hasMatch(lower)) {
        carbs ??= _valueAt(row, column);
      } else if (_fat.hasMatch(lower)) {
        fat ??= _valueAt(row, column);
      } else if (_salt.hasMatch(lower)) {
        salt ??= _valueAt(row, column);
      }
    }

    // Saturates and sugars can never exceed their parent value; when OCR
    // swapped a row, drop the impossible child rather than guess.
    if (sat != null && fat != null && sat > fat + 0.05) sat = null;
    if (sugars != null && carbs != null && sugars > carbs + 0.05) sugars = null;

    return NutritionLabelValues(
      kcal: kcal,
      fat: fat,
      saturatedFat: sat,
      carbs: carbs,
      sugars: sugars,
      fiber: fiber,
      protein: protein,
      salt: salt,
      perMl: perMl,
    );
  }

  /// Compares label energy with fat × 9 + carbs × 4 + protein × 4 +
  /// fibre × 2. Returns null when a core value is missing.
  static LabelEnergyCheck? checkEnergy(NutritionLabelValues v) {
    if (!v.hasCoreValues) return null;
    final computed =
        v.fat! * kcalPerGramFat +
        v.carbs! * kcalPerGramCarbs +
        v.protein! * kcalPerGramProtein +
        (v.fiber ?? 0) * kcalPerGramFiber;
    final label = v.kcal!;
    final top = math.max(label, computed);
    final difference = top <= 0 ? 0.0 : (label - computed).abs() / top;
    // Very low-energy foods (water, diet drinks) get an absolute margin.
    final passes =
        difference <= energyTolerance || (label - computed).abs() <= 5;
    return LabelEnergyCheck(
      labelKcal: label,
      computedKcal: computed,
      difference: difference,
      passes: passes,
    );
  }

  // --- helpers ---------------------------------------------------------

  static String _normalise(String row) {
    var r = row.replaceAll(' ', ' ').trim();
    // Join a decimal split by OCR ("3 ,4 g", "3, 4 g").
    r = r.replaceAllMapped(
      RegExp(r'(\d)\s*([.,])\s*(\d)'),
      (m) => '${m[1]}${m[2]}${m[3]}',
    );
    // Common OCR letter/digit confusions inside numbers: "O"/"o" for 0,
    // "l"/"I" for 1, when sandwiched by digits or before a unit.
    r = r.replaceAllMapped(
      RegExp(r'(?<=\d|[.,])[oO](?=\d|[.,]\d|\s*g\b|\s*%|$)'),
      (_) => '0',
    );
    r = r.replaceAllMapped(
      RegExp(r'(?<=[.,]|\d)[lI](?=\d|\s*g\b)'),
      (_) => '1',
    );
    r = r.replaceAllMapped(
      RegExp(r'\bk\s+(cal|j)\b', caseSensitive: false),
      (m) => 'k${m[1]}',
    );
    return r;
  }

  /// The index of the per-100 g column among a row's numbers, from a header
  /// row such as "Por 100 g | Por ración (30 g) | %IR". Defaults to 0.
  static int _per100Column(List<String> rows) {
    for (final row in rows.take(8)) {
      final lower = row.toLowerCase();
      final match = _per100.firstMatch(lower);
      if (match == null) continue;
      // Count the other "per" columns that appear before "100 g".
      final before = lower.substring(0, match.start);
      final earlier = RegExp(
        r'(\d+(?:[.,]\d+)?\s*(g|ml)\b)|%',
      ).allMatches(before).length;
      return earlier;
    }
    return 0;
  }

  static List<_NumberToken> _numbers(String row) {
    final tokens = <_NumberToken>[];
    for (final m in _number.allMatches(row)) {
      final after = row.substring(m.end).trimLeft().toLowerCase();
      final isPercent = after.startsWith('%');
      final value = double.tryParse(m[1]!.replaceAll(',', '.'));
      if (value == null) continue;
      tokens.add(_NumberToken(value, isPercent, after));
    }
    return tokens;
  }

  /// The [column]-th gram value in a row, skipping percentages (%IR / %RI)
  /// and "<" signs.
  static double? _valueAt(String row, int column) {
    final values = _numbers(row).where((t) => !t.isPercent).toList();
    if (values.isEmpty) return null;
    final index = column < values.length ? column : 0;
    final v = values[index].value;
    return v.isFinite && v >= 0 && v <= 100 ? v : null;
  }

  /// Energy in kcal from a row like "1035 kJ / 247 kcal" or "247kcal",
  /// ignoring kJ. When only kJ is present, converts (1 kcal = 4.184 kJ).
  static double? _readKcal(String row, int column) {
    final lower = row.toLowerCase();
    double? pick(Iterable<RegExpMatch> matches, double max) {
      final values = [
        for (final m in matches)
          if (double.tryParse(m[1]!.replaceAll(',', '.')) case final v?)
            if (v >= 0 && v <= max) v,
      ];
      if (values.isEmpty) return null;
      return values[column < values.length ? column : 0];
    }

    final kcal =
        pick(RegExp(r'(\d+(?:[.,]\d+)?)\s*kcal').allMatches(lower), 900) ??
        pick(RegExp(r'kcal\D{0,3}(\d+(?:[.,]\d+)?)').allMatches(lower), 900);
    if (kcal != null) return kcal;
    final kj = pick(RegExp(r'(\d+(?:[.,]\d+)?)\s*kj').allMatches(lower), 3800);
    if (kj != null) return double.parse((kj / 4.184).toStringAsFixed(0));
    return null;
  }
}

class _NumberToken {
  final double value;
  final bool isPercent;
  final String after;

  _NumberToken(this.value, this.isPercent, this.after);
}
