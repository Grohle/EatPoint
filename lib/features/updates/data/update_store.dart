import 'package:opennutritracker/core/utils/hive_db_provider.dart';

/// Whether EatPoint looks for updates when it opens, and which release it
/// last offered, so "Later" doesn't bring the same one back on every start.
class UpdateStore {
  static const _autoKey = 'updates.auto';
  static const _offeredKey = 'updates.offered';
  static const _offeredAtKey = 'updates.offeredAt';

  /// How long "Later" keeps one release quiet.
  static const remindAfter = Duration(days: 1);

  final HiveDBProvider _db;

  UpdateStore(this._db);

  /// On unless the user turned it off.
  bool get autoCheck => _db.pointsSettingsBox.get(_autoKey) != 'false';

  Future<void> setAutoCheck(bool value) =>
      _db.pointsSettingsBox.put(_autoKey, value.toString());

  /// Whether [version] may be offered again on opening the app.
  bool shouldOffer(String version, {DateTime? now}) {
    if (_db.pointsSettingsBox.get(_offeredKey) != version) return true;
    final at = DateTime.tryParse(
      _db.pointsSettingsBox.get(_offeredAtKey) ?? '',
    );
    if (at == null) return true;
    return (now ?? DateTime.now()).difference(at) >= remindAfter;
  }

  Future<void> markOffered(String version, {DateTime? now}) async {
    await _db.pointsSettingsBox.put(_offeredKey, version);
    await _db.pointsSettingsBox.put(
      _offeredAtKey,
      (now ?? DateTime.now()).toIso8601String(),
    );
  }
}
