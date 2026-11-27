import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/app_update.dart';

/// Asks GitHub whether a newer EatPoint release exists.
///
/// One unauthenticated request to the public releases list: no account, no
/// identifier, nothing about the user is sent.
class UpdateChecker {
  static const repository = 'Grohle/EatPoint';
  static final releasesUrl = Uri.parse(
    'https://api.github.com/repos/$repository/releases?per_page=10',
  );

  final http.Client _client;

  UpdateChecker(this._client);

  /// The newest release above [installed], or null when it is up to date.
  ///
  /// [abis] are the phone's processor types, best first (Android's
  /// `supportedAbis`); they pick the APK. Throws on a network or server
  /// error, so a manual check can say so.
  Future<AppUpdate?> check({
    required String installed,
    List<String> abis = const [],
  }) async {
    final current = AppVersion.tryParse(installed);
    if (current == null) return null;
    final response = await _client
        .get(
          releasesUrl,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'EatPoint-app',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw UpdateCheckException('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw const UpdateCheckException('unexpected reply');

    AppUpdate? best;
    for (final release in decoded) {
      if (release is! Map || release['draft'] == true) continue;
      final version = AppVersion.tryParse('${release['tag_name'] ?? ''}');
      if (version == null || !(version > current)) continue;
      if (best != null && !(version > best.version)) continue;
      best = AppUpdate(
        version: version,
        pageUrl: '${release['html_url'] ?? _fallbackPage(version)}',
        notes: '${release['body'] ?? ''}',
        apkUrl: _apkFor(release['assets'], abis),
      );
    }
    return best;
  }

  static String _fallbackPage(AppVersion v) =>
      'https://github.com/$repository/releases/tag/v$v';

  /// The APK built for the first of [abis] the release has; with no ABI
  /// information, the 64-bit ARM one that fits almost every phone.
  static String? _apkFor(Object? assets, List<String> abis) {
    if (assets is! List) return null;
    final apks = <String, String>{};
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = '${asset['name'] ?? ''}';
      final url = asset['browser_download_url'];
      if (!name.endsWith('.apk') || url is! String) continue;
      apks[name] = url;
    }
    for (final abi in [...abis, 'arm64-v8a']) {
      for (final entry in apks.entries) {
        if (entry.key.contains(abi)) return entry.value;
      }
    }
    return apks.length == 1 ? apks.values.single : null;
  }
}

class UpdateCheckException implements Exception {
  final String message;

  const UpdateCheckException(this.message);

  @override
  String toString() => 'UpdateCheckException($message)';
}
