import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:opennutritracker/features/food_db/domain/food_database.dart';

/// What is installed, as the manifest described it.
class FoodDbInfo {
  final int version;
  final String file;
  final int bytes;
  final String sha256;
  final int count;
  final String? generated;
  final List<FoodDbSource> sources;

  const FoodDbInfo({
    required this.version,
    required this.file,
    required this.bytes,
    required this.sha256,
    required this.count,
    this.generated,
    this.sources = const [],
  });

  static FoodDbInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final file = json['file'];
    final sha = json['sha256'];
    if (version is! num || file is! String || sha is! String) return null;
    // Only a plain file name, never a path or a URL.
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(file)) return null;
    return FoodDbInfo(
      version: version.toInt(),
      file: file,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      sha256: sha,
      count: (json['count'] as num?)?.toInt() ?? 0,
      generated: json['generated'] as String?,
      sources: [
        for (final s in json['sources'] as List? ?? const [])
          ?FoodDbSource.fromJson(s),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'file': file,
    'bytes': bytes,
    'sha256': sha256,
    'count': count,
    'generated': generated,
    'sources': [
      for (final s in sources)
        {'id': s.id, 'name': s.name, 'license': s.license, 'url': s.url},
    ],
  };
}

enum FoodDbState { none, loading, ready, downloading, failed }

/// Downloads EatPoint's food database from GitHub, keeps it on the phone
/// and loads it into [FoodDatabase.instance].
class FoodDbService {
  static const baseUrl =
      'https://raw.githubusercontent.com/Grohle/EatPoint/main/data/food_db/';
  static const manifestName = 'manifest.json';
  static const _installedName = 'installed.json';
  static const _dataName = 'foods.json.gz';

  final _log = Logger('FoodDbService');
  final http.Client _client;
  final Future<Directory> Function() _directory;

  final ValueNotifier<FoodDbState> state = ValueNotifier(FoodDbState.none);

  /// 0..1 while downloading.
  final ValueNotifier<double?> progress = ValueNotifier(null);

  FoodDbInfo? _installed;
  FoodDbInfo? get installed => _installed;

  FoodDbService({http.Client? client, Future<Directory> Function()? directory})
    : _client = client ?? http.Client(),
      _directory = directory ?? _defaultDirectory;

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/food_db');
  }

  Future<File> _file(String name) async =>
      File('${(await _directory()).path}/$name');

  Future<void>? _loading;

  /// Loads the installed database, if any. Never throws.
  Future<void> load() => _loading = _load();

  Future<void> _load() async {
    try {
      final info = await _file(_installedName);
      final data = await _file(_dataName);
      if (!await info.exists() || !await data.exists()) {
        state.value = FoodDbState.none;
        return;
      }
      state.value = FoodDbState.loading;
      _installed = FoodDbInfo.fromJson(jsonDecode(await info.readAsString()));
      final bytes = await data.readAsBytes();
      final db = await Isolate.run(() => FoodDatabase.parseGzip(bytes));
      FoodDatabase.setInstance(db);
      state.value = FoodDbState.ready;
    } catch (e) {
      _log.warning('Could not load the food database: $e');
      FoodDatabase.setInstance(null);
      state.value = FoodDbState.failed;
    }
  }

  /// The manifest of the latest database on GitHub.
  Future<FoodDbInfo> fetchManifest() async {
    final response = await _client
        .get(Uri.parse('$baseUrl$manifestName'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('Manifest: HTTP ${response.statusCode}');
    }
    final info = FoodDbInfo.fromJson(jsonDecode(response.body));
    if (info == null) throw const FormatException('Bad manifest');
    return info;
  }

  /// Whether GitHub has a newer database than the installed one.
  Future<bool> hasUpdate() async {
    final latest = await fetchManifest();
    final current = _installed;
    return current == null ||
        latest.version > current.version ||
        latest.sha256 != current.sha256;
  }

  /// EatPoint: when a database is installed and GitHub has a newer one,
  /// installs it. Returns the new version, or null when nothing changed.
  /// Throws when the check or the download fails; what was installed stays.
  Future<int?> updateIfNewer() async {
    await _loading;
    if (state.value != FoodDbState.ready || _installed == null) return null;
    if (!await hasUpdate()) return null;
    await download();
    return _installed?.version;
  }

  /// Downloads the latest database, checks it and installs it. Throws when
  /// the download or the check fails; what was installed stays.
  Future<void> download() async {
    final previous = state.value;
    state.value = FoodDbState.downloading;
    progress.value = 0;
    try {
      final info = await fetchManifest();
      final request = http.Request('GET', Uri.parse('$baseUrl${info.file}'));
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw HttpException('Database: HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? info.bytes;
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        if (total > 0) progress.value = (bytes.length / total).clamp(0, 1);
      }
      final digest = await Sha256().hash(bytes);
      final hex = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      if (hex != info.sha256) {
        throw const FormatException('The downloaded file is damaged');
      }
      // Check it reads before replacing what works.
      final db = await Isolate.run(
        () => FoodDatabase.parseGzip(Uint8List.fromList(bytes)),
      );
      final dir = await _directory();
      await dir.create(recursive: true);
      await (await _file(_dataName)).writeAsBytes(bytes, flush: true);
      await (await _file(
        _installedName,
      )).writeAsString(jsonEncode(info.toJson()), flush: true);
      _installed = info;
      FoodDatabase.setInstance(db);
      state.value = FoodDbState.ready;
    } catch (e) {
      _log.warning('Food database download failed: $e');
      state.value = previous == FoodDbState.ready
          ? FoodDbState.ready
          : FoodDbState.failed;
      rethrow;
    } finally {
      progress.value = null;
    }
  }

  /// Removes the database from the phone.
  Future<void> delete() async {
    for (final name in [_dataName, _installedName]) {
      final file = await _file(name);
      if (await file.exists()) await file.delete();
    }
    _installed = null;
    FoodDatabase.setInstance(null);
    state.value = FoodDbState.none;
  }
}
