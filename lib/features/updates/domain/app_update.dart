/// A version string such as `0.3.2`, `v0.3.2` or `0.3.2+6`, compared by its
/// numbers. The build number after `+` and anything after `-` are ignored.
class AppVersion implements Comparable<AppVersion> {
  final List<int> parts;

  const AppVersion(this.parts);

  static AppVersion? tryParse(String text) {
    var t = text.trim();
    if (t.startsWith('v') || t.startsWith('V')) t = t.substring(1);
    t = t.split('+').first.split('-').first;
    if (t.isEmpty) return null;
    final parts = <int>[];
    for (final piece in t.split('.')) {
      final n = int.tryParse(piece);
      if (n == null) return null;
      parts.add(n);
    }
    return AppVersion(parts);
  }

  @override
  int compareTo(AppVersion other) {
    final length = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  String toString() => parts.join('.');
}

/// A newer EatPoint release than the one installed.
class AppUpdate {
  final AppVersion version;

  /// The release page, with the notes and every download.
  final String pageUrl;

  /// The APK for this phone's processor, when the release has one.
  final String? apkUrl;

  /// The release notes, as written on the page (Markdown).
  final String notes;

  const AppUpdate({
    required this.version,
    required this.pageUrl,
    required this.notes,
    this.apkUrl,
  });

  /// Where "Download" goes: the APK itself, else the page.
  String get downloadUrl => apkUrl ?? pageUrl;
}
