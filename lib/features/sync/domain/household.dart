import 'dart:convert';
import 'dart:math';

import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/sync/domain/household_crypto.dart';
import 'package:opennutritracker/features/sync/domain/sync_backend.dart';
import 'package:opennutritracker/features/sync/domain/household_menu.dart';

/// This phone's membership of a shared household.
class Household {
  /// Random 128-bit id, hex. Scopes the blobs on the backend and is
  /// authenticated in every encrypted blob.
  final String householdId;

  /// This member's random id, hex.
  final String memberId;

  /// How this member is shown on the other phones (an initial or a name).
  final String memberName;

  final SyncBackendConfig backend;

  /// Other members seen so far: id -> name.
  final Map<String, String> members;

  final DateTime? lastSyncAt;

  const Household({
    required this.householdId,
    required this.memberId,
    required this.memberName,
    required this.backend,
    this.members = const {},
    this.lastSyncAt,
  });

  static String randomHexId([int bytes = 16]) {
    final random = Random.secure();
    return List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  String get blobName => blobNameFor(memberId);

  static String blobNameFor(String memberId) => 'member-$memberId.json.enc';

  static String? memberIdFromBlob(String name) {
    final match = RegExp(
      r'^member-([0-9a-f]{8,64})\.json\.enc$',
    ).firstMatch(name);
    return match?.group(1);
  }

  Household copyWith({
    String? memberName,
    SyncBackendConfig? backend,
    Map<String, String>? members,
    DateTime? lastSyncAt,
  }) => Household(
    householdId: householdId,
    memberId: memberId,
    memberName: memberName ?? this.memberName,
    backend: backend ?? this.backend,
    members: members ?? this.members,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
  );

  Map<String, dynamic> toJson() => {
    'householdId': householdId,
    'memberId': memberId,
    'memberName': memberName,
    'backend': backend.toJson(),
    'members': members,
    if (lastSyncAt != null) 'lastSyncAt': lastSyncAt!.toIso8601String(),
  };

  static Household? fromJson(Object? json) {
    if (json is! Map) return null;
    final backend = SyncBackendConfig.fromJson(json['backend']);
    final householdId = json['householdId'];
    final memberId = json['memberId'];
    if (backend == null || householdId is! String || memberId is! String) {
      return null;
    }
    final members = json['members'];
    return Household(
      householdId: householdId,
      memberId: memberId,
      memberName: json['memberName'] as String? ?? '',
      backend: backend,
      members: {
        if (members is Map)
          for (final e in members.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      lastSyncAt: DateTime.tryParse(json['lastSyncAt'] as String? ?? ''),
    );
  }
}

/// What one member publishes: their planned days around the current week
/// and their shopping-list ticks.
class MemberSnapshot {
  static const formatVersion = 1;

  final String memberId;
  final String name;
  final DateTime updatedAt;
  final List<DayPlan> days;

  /// Week start key (yyyy-mm-dd) -> list state.
  final Map<String, ShoppingListState> shopping;

  /// EatPoint: the member's meals, points and diet; null when they don't
  /// share it.
  final MemberProfile? profile;

  /// Changes this member made to other members' menus, not yet confirmed.
  final List<MenuEdit> edits;

  /// Ids of the changes others made to this member's menu that this
  /// member's phone has handled.
  final Set<String> applied;

  const MemberSnapshot({
    required this.memberId,
    required this.name,
    required this.updatedAt,
    this.days = const [],
    this.shopping = const {},
    this.profile,
    this.edits = const [],
    this.applied = const {},
  });

  /// Whether other members may change this member's menu.
  bool get allowsEdits => profile?.allowEdits ?? false;

  /// The same snapshot with [day] in place of the plan for its date.
  MemberSnapshot withDay(DayPlan day) => MemberSnapshot(
    memberId: memberId,
    name: name,
    updatedAt: updatedAt,
    days: [
      for (final d in days)
        if (d.date != day.date) d,
      day,
    ],
    shopping: shopping,
    profile: profile,
    edits: edits,
    applied: applied,
  );

  DayPlan? dayFor(DateTime date) {
    final d = DayPlan.dateOnly(date);
    for (final day in days) {
      if (day.date == d) return day;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'v': formatVersion,
    'memberId': memberId,
    'name': name,
    'updatedAt': updatedAt.toIso8601String(),
    'days': [for (final d in days) d.toJson()],
    'shopping': {for (final e in shopping.entries) e.key: e.value.toJson()},
    if (profile != null) 'profile': profile!.toJson(),
    if (edits.isNotEmpty) 'edits': [for (final e in edits) e.toJson()],
    if (applied.isNotEmpty) 'applied': applied.toList(),
  };

  static MemberSnapshot? fromJson(Map<String, dynamic> json) {
    final memberId = json['memberId'];
    if (memberId is! String) return null;
    final rawDays = json['days'];
    final rawShopping = json['shopping'];
    final rawEdits = json['edits'];
    final rawApplied = json['applied'];
    return MemberSnapshot(
      profile: MemberProfile.fromJson(json['profile']),
      edits: [
        if (rawEdits is List) ...rawEdits.map(MenuEdit.fromJson).nonNulls,
      ],
      applied: {
        if (rawApplied is List)
          for (final id in rawApplied)
            if (id is String) id,
      },
      memberId: memberId,
      name: json['name'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      days: [
        if (rawDays is List)
          for (final d in rawDays)
            if (d is Map<String, dynamic>)
              DayPlan.fromJson(
                d,
                DateTime.tryParse(d['date'] as String? ?? '') ?? DateTime.now(),
              ),
      ],
      shopping: {
        if (rawShopping is Map)
          for (final e in rawShopping.entries)
            if (e.key is String && e.value is Map<String, dynamic>)
              e.key as String: ShoppingListState.fromJson(
                e.value as Map<String, dynamic>,
              ),
      },
    );
  }
}

/// Everything another phone needs to join: shown as a QR code on the first
/// phone and scanned in person. It carries the household key and the
/// backend secret, so it is never sent anywhere.
class HouseholdInvite {
  static const type = 'eatpoint-household';

  final String householdId;
  final HouseholdKey key;
  final SyncBackendConfig backend;
  final String? backendSecret;

  const HouseholdInvite({
    required this.householdId,
    required this.key,
    required this.backend,
    this.backendSecret,
  });

  String encode() => jsonEncode({
    't': type,
    'v': 1,
    'h': householdId,
    'k': key.toBase64(),
    'b': backend.toJson(),
    if (backendSecret != null) 's': backendSecret,
  });

  static HouseholdInvite? decode(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map || json['t'] != type) return null;
      final key = HouseholdKey.fromBase64(json['k'] as String? ?? '');
      final backend = SyncBackendConfig.fromJson(json['b']);
      final householdId = json['h'];
      if (key == null ||
          backend == null ||
          householdId is! String ||
          !RegExp(r'^[0-9a-f]{32,64}$').hasMatch(householdId)) {
        return null;
      }
      return HouseholdInvite(
        householdId: householdId,
        key: key,
        backend: backend,
        backendSecret: json['s'] as String?,
      );
    } on FormatException {
      return null;
    }
  }
}
