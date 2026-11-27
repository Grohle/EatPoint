import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_checker.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';

/// Stores the active profile's [DietProfile] in EatPoint's box.
class DietProfileStore {
  static const _key = 'diet';

  final _log = Logger('DietProfileStore');
  final HiveDBProvider _db;

  /// Bumped on every change so open screens can update.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  DietProfileStore(this._db);

  DietProfile get() {
    final raw = _db.pointsSettingsBox.get(_key);
    if (raw == null) return DietProfile.empty;
    try {
      return DietProfile.fromJson(jsonDecode(raw));
    } on FormatException catch (e) {
      _log.warning('Unreadable diet profile, using none: $e');
      return DietProfile.empty;
    }
  }

  Future<void> save(DietProfile profile) async {
    await _db.pointsSettingsBox.put(_key, jsonEncode(profile.toJson()));
    revision.value++;
  }

  /// The checker for the active profile, or null when none is set up (or
  /// the store is not registered, as in some tests).
  static DietChecker? checker() {
    if (!locator.isRegistered<DietProfileStore>()) return null;
    final profile = locator<DietProfileStore>().get();
    return profile.isEmpty ? null : DietChecker(profile);
  }
}
