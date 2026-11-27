import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/secure_app_storage_provider.dart';
import 'package:opennutritracker/features/sync/domain/household.dart';
import 'package:opennutritracker/features/sync/domain/household_crypto.dart';

/// Keeps the household membership of the active profile: the non-secret
/// part in EatPoint's per-profile box, the household key and the backend
/// secret in the platform keystore, and the latest snapshot of each other
/// member for offline use.
class HouseholdStore {
  static const _householdKey = 'household';
  static const _memberPrefix = 'household:member:';

  final HiveDBProvider _db;
  final FlutterSecureStorage _secure;

  /// Bumped when the household or a member snapshot changes.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  HouseholdStore(this._db, [FlutterSecureStorage? secure])
    : _secure = secure ?? SecureAppStorageProvider.secureAppStorage;

  String get _profile => _db.activeProfileId;
  String get _keyTag => 'EatPointHouseholdKey_$_profile';
  String get _secretTag => 'EatPointHouseholdBackendSecret_$_profile';

  Household? getHousehold() {
    final raw = _db.pointsSettingsBox.get(_householdKey);
    if (raw == null) return null;
    try {
      return Household.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> saveHousehold(Household household) async {
    await _db.pointsSettingsBox.put(
      _householdKey,
      jsonEncode(household.toJson()),
    );
    revision.value++;
  }

  Future<HouseholdKey?> readKey() async {
    final raw = await _secure.read(key: _keyTag);
    return raw == null ? null : HouseholdKey.fromBase64(raw);
  }

  Future<void> writeKey(HouseholdKey key) =>
      _secure.write(key: _keyTag, value: key.toBase64());

  Future<String?> readBackendSecret() => _secure.read(key: _secretTag);

  Future<void> writeBackendSecret(String? secret) => secret == null
      ? _secure.delete(key: _secretTag)
      : _secure.write(key: _secretTag, value: secret);

  List<MemberSnapshot> otherMembers() {
    final members = <MemberSnapshot>[];
    for (final key in _db.pointsSettingsBox.keys) {
      if (key is! String || !key.startsWith(_memberPrefix)) continue;
      final raw = _db.pointsSettingsBox.get(key);
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) {
          final snapshot = MemberSnapshot.fromJson(json);
          if (snapshot != null) members.add(snapshot);
        }
      } on FormatException {
        continue;
      }
    }
    members.sort((a, b) => a.name.compareTo(b.name));
    return members;
  }

  Future<void> saveMember(MemberSnapshot snapshot) async {
    await _db.pointsSettingsBox.put(
      '$_memberPrefix${snapshot.memberId}',
      jsonEncode(snapshot.toJson()),
    );
    revision.value++;
  }

  /// Forgets the household on this phone (the other members keep theirs).
  Future<void> leave() async {
    final keys = _db.pointsSettingsBox.keys
        .whereType<String>()
        .where((k) => k == _householdKey || k.startsWith(_memberPrefix))
        .toList();
    await _db.pointsSettingsBox.deleteAll(keys);
    await _secure.delete(key: _keyTag);
    await _secure.delete(key: _secretTag);
    revision.value++;
  }
}
