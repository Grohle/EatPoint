import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'package:opennutritracker/features/menu_import/domain/imported_menu.dart';

/// Reads a menu written as plain text or pasted as a table (from a
/// spreadsheet, a document or a website) into days, meals and foods.
///
/// Understands, in English and Spanish:
/// - day headings: weekday names ("Monday", "Lunes", "Mon", "L"), dates
///   ("27/11", "2026-11-27") and numbered days ("Day 3", "Día 3");
/// - meal headings: "Breakfast", "Desayuno", "Media mañana", "Cena", the
///   user's own meal names passed in [mealNames], with or without a colon,
///   and with foods on the same line ("Lunch: rice 150 g, chicken");
/// - foods with amounts in any order ("150 g rice", "rice 150g",
///   "100 gr de arroz", "2 eggs") and optional points ("rice 1.5 pts");
/// - tables: a week grid (days across, meals down, or the other way round)
///   and long tables with one food per row (day | meal | food | amount).
///
/// Lines it cannot place (titles, notes) are skipped. The result keeps the
/// labels as written; matching them to the user's meals happens later.
class MenuTextParser {
  MenuTextParser._();

  static ImportedMenu parse(String input, {List<String> mealNames = const []}) {
    final text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = text
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return const ImportedMenu([]);
    final table = _asTable(lines);
    if (table != null) {
      final fromTable = _parseTable(table, mealNames);
      if (!fromTable.isEmpty) return fromTable;
    }
    return _parseText(lines, mealNames);
  }

  // --- vocabulary -------------------------------------------------------

  static const _weekdays = <String, int>{
    'monday': 1,
    'mon': 1,
    'lunes': 1,
    'lun': 1,
    'tuesday': 2,
    'tue': 2,
    'tues': 2,
    'martes': 2,
    'mar': 2,
    'wednesday': 3,
    'wed': 3,
    'miercoles': 3,
    'mie': 3,
    'mier': 3,
    'thursday': 4,
    'thu': 4,
    'thur': 4,
    'thurs': 4,
    'jueves': 4,
    'jue': 4,
    'friday': 5,
    'fri': 5,
    'viernes': 5,
    'vie': 5,
    'saturday': 6,
    'sat': 6,
    'sabado': 6,
    'sab': 6,
    'sunday': 7,
    'sun': 7,
    'domingo': 7,
    'dom': 7,
  };

  /// Meal words in English and Spanish. The value is only a hint for the
  /// matcher; the label itself is kept.
  static const mealWords = <String>[
    'breakfast',
    'desayuno',
    'brunch',
    'mid-morning',
    'mid morning',
    'midmorning',
    'media manana',
    'media-manana',
    'almuerzo',
    'elevenses',
    'lunch',
    'comida',
    'afternoon snack',
    'merienda',
    'snack',
    'snacks',
    'tentempie',
    'picoteo',
    'aperitivo',
    'dinner',
    'cena',
    'supper',
    'late snack',
    'recena',
    'resopon',
    'pre-workout',
    'pre workout',
    'preentreno',
    'pre-entreno',
    'antes de entrenar',
    'post-workout',
    'post workout',
    'postentreno',
    'post-entreno',
    'despues de entrenar',
  ];

  static final _dayNumber = RegExp(
    r'^(?:day|dia)\s*(\d{1,2})\b',
    caseSensitive: false,
  );
  static final _isoDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');
  static final _dmyDate = RegExp(
    r'\b(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2,4}))?\b',
  );
  static final _points = RegExp(
    r'\(?\s*(\d+(?:[.,]\d+)?)\s*(?:pts?|puntos?|points?)\b\.?\s*\)?',
    caseSensitive: false,
  );
  static final _bullet = RegExp(r'^\s*(?:[-*•·▪◦–—>]+|\d+[.)]\s+)\s*');

  /// Lower case without accents, for matching words.
  static String fold(String s) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    final buffer = StringBuffer();
    for (final ch in s.toLowerCase().runes) {
      final c = String.fromCharCode(ch);
      final i = from.indexOf(c);
      buffer.write(i >= 0 ? to[i] : c);
    }
    return buffer.toString();
  }

  /// The weekday (1-7) [cell] names, when it is only a weekday (and maybe
  /// a date), like "Lunes", "Mon 27/11", "MONDAY:".
  static int? weekdayOf(String cell) {
    final words = fold(cell)
        .replaceAll(RegExp(r'[^a-z0-9/ .-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty || words.length > 4) return null;
    final first = words.first.replaceAll(RegExp(r'[.]$'), '');
    final day = _weekdays[first];
    if (day == null) return null;
    // "Mar" alone is Tuesday in Spanish; "mar 3" too. Anything with more
    // words must be a date or a number, not a food.
    final rest = words.skip(1).join(' ');
    if (rest.isNotEmpty && !RegExp(r'^[\d/ .-]+$').hasMatch(rest)) {
      return null;
    }
    return day;
  }

  static DateTime? dateOf(String cell, {DateTime? now}) {
    final iso = _isoDate.firstMatch(cell);
    if (iso != null) {
      return _safeDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final dmy = _dmyDate.firstMatch(cell);
    if (dmy != null) {
      final day = int.parse(dmy.group(1)!);
      final month = int.parse(dmy.group(2)!);
      var year = dmy.group(3) == null
          ? (now ?? DateTime.now()).year
          : int.parse(dmy.group(3)!);
      if (year < 100) year += 2000;
      return _safeDate(year, month, day);
    }
    return null;
  }

  static DateTime? _safeDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, m, d);
    return date.month == m ? date : null;
  }

  /// Whether [line] is a day heading, and which day.
  static ImportedDay? dayHeading(String line) {
    final clean = line.replaceAll(_bullet, '').trim();
    final stripped = clean.replaceAll(RegExp(r'[:#*_=]+'), ' ').trim();
    if (stripped.isEmpty || stripped.length > 40) return null;
    final weekday = weekdayOf(stripped);
    final number = _dayNumber.firstMatch(fold(stripped));
    final onlyDate = RegExp(r'^[\d/.\- ]+$').hasMatch(stripped);
    final date = (weekday != null || onlyDate || number != null)
        ? dateOf(stripped)
        : null;
    if (weekday == null && number == null && date == null) return null;
    return ImportedDay(
      weekday: weekday,
      date: date,
      index: number == null ? null : int.tryParse(number.group(1)!),
      label: stripped,
    );
  }

  /// Splits "Lunch: rice, chicken" into the meal label and the rest when
  /// the line starts with a meal word or one of [mealNames].
  static ({String label, String rest})? mealHeading(
    String line,
    List<String> mealNames,
  ) {
    final clean = line.replaceAll(_bullet, '').trim();
    final folded = fold(clean);
    final candidates = [...mealNames.map(fold), ...mealWords]
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final word in candidates) {
      if (word.isEmpty || !folded.startsWith(word)) continue;
      final after = clean.substring(word.length);
      // A whole word: followed by nothing, a separator or a space.
      if (after.isNotEmpty && !RegExp(r'^[\s:\-–—(]').hasMatch(after)) {
        continue;
      }
      final colon = RegExp(
        r'^\s*(?:\([^)]*\))?\s*[:\-–—]\s*',
      ).firstMatch(after);
      final rest = colon == null
          ? after.trim()
          : after.substring(colon.end).trim();
      // "Comida rápida de pollo" is a food, not the meal "Comida", unless
      // the label stands alone or ends in a colon.
      if (colon == null && rest.isNotEmpty) continue;
      return (label: clean.substring(0, word.length), rest: rest);
    }
    return null;
  }

  // --- foods ------------------------------------------------------------

  /// The foods in one cell or line: "150 g rice, 1 egg + salad (0.5 pts)".
  static List<ImportedFood> foods(String text) {
    var cleaned = text.replaceAll(_bullet, '').trim();
    if (cleaned.isEmpty) return const [];
    // Units the shared parser does not know, and the Spanish "de".
    cleaned = cleaned
        .replaceAllMapped(
          RegExp(r'(\d)\s*(?:grs?|gramos?|grams?)\b\.?', caseSensitive: false),
          (m) => '${m[1]}g',
        )
        .replaceAllMapped(
          RegExp(
            r'(\d)\s*(?:mls?|mililitros?|millilit(?:re|er)s?)\b\.?',
            caseSensitive: false,
          ),
          (m) => '${m[1]}ml',
        )
        .replaceAllMapped(
          RegExp(r'(\d\s*(?:g|ml|kg|l))\s+(?:de|of)\s+', caseSensitive: false),
          (m) => '${m[1]} ',
        )
        .replaceAll(
          RegExp(r'\s+(?:y|and|con|with)\s+', caseSensitive: false),
          ', ',
        );
    final foods = <ImportedFood>[];
    for (final segment in cleaned.split(RegExp(r'[;+\n]|(?<!\d),|,(?!\d)'))) {
      final s = segment.trim();
      if (s.isEmpty) continue;
      final pointsMatch = _points.firstMatch(s);
      final points = pointsMatch == null
          ? null
          : double.tryParse(pointsMatch.group(1)!.replaceAll(',', '.'));
      final withoutPoints =
          (pointsMatch == null
                  ? s
                  : s.replaceRange(pointsMatch.start, pointsMatch.end, ' '))
              .replaceAll(RegExp(r'\(\s*\)'), '')
              .trim();
      if (withoutPoints.isEmpty) continue;
      final parsed = parseMealText(withoutPoints).items;
      if (parsed.isEmpty) continue;
      final item = parsed.first;
      double? amount;
      String? unit;
      double? count;
      switch (item.unit) {
        case 'g':
          amount = item.quantity;
          unit = 'g';
        case 'kg':
          amount = item.quantity == null ? null : item.quantity! * 1000;
          unit = 'g';
        case 'ml':
          amount = item.quantity;
          unit = 'ml';
        case 'l':
          amount = item.quantity == null ? null : item.quantity! * 1000;
          unit = 'ml';
        case null:
          count = item.quantity;
        default:
          break;
      }
      final name = item.query.replaceAll(
        RegExp(r'^[\s:\-–—]+|[\s:\-–—.]+$'),
        '',
      );
      if (name.isEmpty || !RegExp(r'\p{L}', unicode: true).hasMatch(name)) {
        continue;
      }
      foods.add(
        ImportedFood(
          name: name,
          amount: amount,
          unit: unit,
          count: count,
          points: points,
        ),
      );
    }
    return foods;
  }

  // --- plain text ---------------------------------------------------------

  static ImportedMenu _parseText(List<String> lines, List<String> mealNames) {
    final days = <ImportedDay>[];
    ImportedDay? day;
    var meals = <ImportedMeal>[];
    String? mealLabel;
    var mealFoods = <ImportedFood>[];

    void closeMeal() {
      if (mealLabel != null || mealFoods.isNotEmpty) {
        meals.add(ImportedMeal(label: mealLabel, foods: mealFoods));
      }
      mealLabel = null;
      mealFoods = <ImportedFood>[];
    }

    void closeDay() {
      closeMeal();
      if (day != null || meals.isNotEmpty) {
        final d = day ?? const ImportedDay();
        days.add(
          ImportedDay(
            date: d.date,
            weekday: d.weekday,
            index: d.index,
            label: d.label,
            meals: meals,
          ),
        );
      }
      meals = <ImportedMeal>[];
    }

    for (final line in lines) {
      final heading = dayHeading(line);
      if (heading != null) {
        closeDay();
        day = heading;
        continue;
      }
      final meal = mealHeading(line, mealNames);
      if (meal != null) {
        closeMeal();
        mealLabel = meal.label;
        mealFoods.addAll(foods(meal.rest));
        continue;
      }
      // A heading-like line ending in ":" that is neither a day nor a meal
      // (e.g. "Pre-cama:") starts a meal with that label.
      final trimmed = line.trim();
      if (trimmed.endsWith(':') && trimmed.length <= 32) {
        closeMeal();
        mealLabel = trimmed.substring(0, trimmed.length - 1).trim();
        continue;
      }
      mealFoods.addAll(foods(line));
    }
    closeDay();
    // A title or a note above the first day heading ("Week 1 menu") is not
    // a day of its own.
    final anyDated = days.any(
      (d) => d.weekday != null || d.date != null || d.index != null,
    );
    if (anyDated) {
      days.removeWhere(
        (d) =>
            d.weekday == null &&
            d.date == null &&
            d.index == null &&
            d.meals.every((m) => m.label == null),
      );
    }
    return ImportedMenu(days.where((d) => !d.isEmpty).toList());
  }

  // --- tables -------------------------------------------------------------

  /// Splits [lines] into cells when they look like a table: most lines
  /// share a tab, '|' or ';' separator with the same number of cells.
  static List<List<String>>? _asTable(List<String> lines) {
    for (final sep in ['\t', '|', ';']) {
      final rows = [
        for (final l in lines)
          if (l.contains(sep))
            sep == '|'
                ? l.split(sep).map((c) => c.trim()).toList()._trimEdgeEmpties()
                : l.split(sep).map((c) => c.trim()).toList(),
      ];
      if (rows.length < 2 || rows.length < lines.length * 0.6) continue;
      // Markdown separator rows like |---|---|.
      rows.removeWhere(
        (r) => r.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c) || c.isEmpty),
      );
      final widths = rows.map((r) => r.length).toList();
      final common = widths.where((w) => w == widths.first).length;
      if (widths.first >= 2 && common >= rows.length * 0.6) return rows;
    }
    return null;
  }

  static ImportedMenu _parseTable(
    List<List<String>> rows,
    List<String> mealNames,
  ) {
    final header = rows.first;
    final dayColumns = <int, ImportedDay>{};
    for (var c = 0; c < header.length; c++) {
      final day = dayHeading(header[c]);
      if (day != null) dayColumns[c] = day;
    }
    // Days across, meals down.
    if (dayColumns.length >= 2) {
      final perDay = {for (final c in dayColumns.keys) c: <ImportedMeal>[]};
      for (final row in rows.skip(1)) {
        if (row.isEmpty) continue;
        final label = row.first.trim();
        for (final c in dayColumns.keys) {
          if (c >= row.length || c == 0) continue;
          final f = foods(row[c]);
          if (f.isEmpty) continue;
          perDay[c]!.add(
            ImportedMeal(label: label.isEmpty ? null : label, foods: f),
          );
        }
      }
      return ImportedMenu(
        [
          for (final c in dayColumns.keys)
            ImportedDay(
              weekday: dayColumns[c]!.weekday,
              date: dayColumns[c]!.date,
              index: dayColumns[c]!.index,
              label: dayColumns[c]!.label,
              meals: perDay[c]!,
            ),
        ].where((d) => !d.isEmpty).toList(),
      );
    }
    // Meals across, days down.
    final mealColumns = <int, String>{};
    for (var c = 0; c < header.length; c++) {
      final meal = mealHeading(header[c], mealNames);
      if (meal != null && meal.rest.isEmpty) mealColumns[c] = header[c].trim();
    }
    if (mealColumns.length >= 2) {
      final days = <ImportedDay>[];
      for (final row in rows.skip(1)) {
        if (row.isEmpty) continue;
        final day = dayHeading(row.first) ?? ImportedDay(label: row.first);
        days.add(
          ImportedDay(
            weekday: day.weekday,
            date: day.date,
            index: day.index,
            label: day.label,
            meals: [
              for (final c in mealColumns.keys)
                if (c < row.length && foods(row[c]).isNotEmpty)
                  ImportedMeal(label: mealColumns[c], foods: foods(row[c])),
            ],
          ),
        );
      }
      return ImportedMenu(days.where((d) => !d.isEmpty).toList());
    }
    return _parseLongTable(rows, mealNames);
  }

  /// One food per row: day | meal | food | amount | points, in any column
  /// order, with or without a header row.
  static ImportedMenu _parseLongTable(
    List<List<String>> rows,
    List<String> mealNames,
  ) {
    int? col(List<String> names) {
      for (var c = 0; c < rows.first.length; c++) {
        final h = fold(rows.first[c]);
        if (names.any((n) => h == n || h.startsWith(n))) return c;
      }
      return null;
    }

    final dayCol = col(['day', 'dia', 'fecha', 'date']);
    final mealCol = col(['meal', 'comida', 'toma', 'ingesta']);
    final foodCol = col(['food', 'alimento', 'plato', 'dish', 'ingrediente']);
    final amountCol = col([
      'amount',
      'cantidad',
      'grams',
      'gramos',
      'g',
      'qty',
    ]);
    final pointsCol = col(['points', 'puntos', 'pts']);
    final hasHeader = foodCol != null;
    final body = hasHeader ? rows.skip(1) : rows;

    final days = <ImportedDay>[];
    ImportedDay? day;
    final mealsOfDay = <String?, List<ImportedFood>>{};

    void closeDay() {
      if (mealsOfDay.isEmpty) return;
      final d = day ?? const ImportedDay();
      days.add(
        ImportedDay(
          weekday: d.weekday,
          date: d.date,
          index: d.index,
          label: d.label,
          meals: [
            for (final e in mealsOfDay.entries)
              ImportedMeal(label: e.key, foods: e.value),
          ],
        ),
      );
      mealsOfDay.clear();
    }

    for (final row in body) {
      String cell(int? c) => c != null && c < row.length ? row[c] : '';
      ImportedDay? rowDay;
      String? meal;
      String foodText;
      if (hasHeader) {
        rowDay = cell(dayCol).isEmpty ? null : dayHeading(cell(dayCol));
        meal = cell(mealCol).isEmpty ? null : cell(mealCol);
        foodText = [
          cell(amountCol),
          cell(foodCol),
          if (cell(pointsCol).isNotEmpty) '${cell(pointsCol)} pts',
        ].where((s) => s.isNotEmpty).join(' ');
      } else {
        final parts = <String>[];
        for (final c in row) {
          if (rowDay == null && dayHeading(c) != null) {
            rowDay = dayHeading(c);
          } else if (meal == null && mealHeading(c, mealNames) != null) {
            meal = c;
          } else {
            parts.add(c);
          }
        }
        foodText = parts.join(' ');
      }
      if (rowDay != null &&
          (day == null ||
              rowDay.weekday != day.weekday ||
              rowDay.date != day.date ||
              rowDay.index != day.index)) {
        closeDay();
        day = rowDay;
      }
      final f = foods(foodText);
      if (f.isEmpty) continue;
      // Merge foods of one meal into one entry.
      (mealsOfDay[meal] ??= []).addAll(f);
    }
    closeDay();
    return ImportedMenu(days.where((d) => !d.isEmpty).toList());
  }
}

extension on List<String> {
  /// "| a | b |" splits into ['', 'a', 'b', '']; drops the empty edges.
  List<String> _trimEdgeEmpties() {
    var list = this;
    if (list.isNotEmpty && list.first.isEmpty) list = list.sublist(1);
    if (list.isNotEmpty && list.last.isEmpty) {
      list = list.sublist(0, list.length - 1);
    }
    return list;
  }
}
