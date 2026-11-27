/// A line of OCR text and its bounding box, in image pixels.
class OcrLine {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const OcrLine(this.text, this.left, this.top, this.right, this.bottom);

  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
}

/// Rebuilds the printed rows of a nutrition table from OCR lines.
///
/// On-device OCR often reads a table column by column (all labels, then all
/// values), which loses which value belongs to which nutrient. Grouping the
/// lines whose vertical centres fall within half a line height of each
/// other, then reading each group left to right, restores the rows.
class LabelRowBuilder {
  static List<String> rows(List<OcrLine> lines) {
    final sorted = [...lines.where((l) => l.text.trim().isNotEmpty)]
      ..sort((a, b) => a.centerY.compareTo(b.centerY));
    final groups = <List<OcrLine>>[];
    for (final line in sorted) {
      final tolerance = (line.height <= 0 ? 10.0 : line.height) * 0.5;
      final group = groups.isEmpty ? null : groups.last;
      if (group != null) {
        final groupCenter =
            group.map((l) => l.centerY).reduce((a, b) => a + b) / group.length;
        if ((line.centerY - groupCenter).abs() <= tolerance) {
          group.add(line);
          continue;
        }
      }
      groups.add([line]);
    }
    return [
      for (final group in groups)
        ([...group]..sort((a, b) => a.left.compareTo(b.left)))
            .map((l) => l.text.trim())
            .join(' '),
    ];
  }
}
