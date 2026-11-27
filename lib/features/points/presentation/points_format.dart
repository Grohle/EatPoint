import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Formats points and grams in the user's language: "2,5" in Spanish,
/// "2.5" in English, with at most two decimals and no trailing zeros.
class PointsFormat {
  final NumberFormat _points;
  final NumberFormat _grams;

  PointsFormat._(String locale)
    : _points = NumberFormat('#,##0.##', locale),
      _grams = NumberFormat('#,##0.#', locale);

  factory PointsFormat.of(BuildContext context) =>
      PointsFormat._(Localizations.localeOf(context).toString());

  @visibleForTesting
  factory PointsFormat.forLocale(String locale) => PointsFormat._(locale);

  String points(double value) => _points.format(_clean(value));

  String grams(double value) => _grams.format(_clean(value));

  /// Parses a number typed with either decimal separator.
  static double? parse(String text) {
    final normalised = text.trim().replaceAll(',', '.');
    if (normalised.isEmpty) return null;
    return double.tryParse(normalised);
  }

  // Avoids "-0" and float noise such as 2.5299999.
  static double _clean(double value) {
    final rounded = (value * 100).round() / 100;
    return rounded == 0 ? 0 : rounded;
  }
}
