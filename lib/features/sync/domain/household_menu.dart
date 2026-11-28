import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/points_calc.dart';
import 'package:opennutritracker/features/diet_profile/domain/diet_profile.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';

/// One of a member's meals, as the household sees it.
class MemberSlot {
  final String id;

  /// The name the member gave it; null for a built-in meal.
  final String? name;
  final IntakeTypeEntity baseType;

  const MemberSlot({required this.id, required this.baseType, this.name});

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'type': baseType.name,
  };

  static MemberSlot? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final type = IntakeTypeEntity.values
        .where((t) => t.name == json['type'])
        .firstOrNull;
    if (id is! String || id.isEmpty || type == null) return null;
    final name = json['name'];
    return MemberSlot(
      id: id,
      baseType: type,
      name: name is String && name.isNotEmpty ? name : null,
    );
  }
}

/// What a member shares so the others can plan for them: their meals, the
/// points and fibre of each, their diet, and whether others may change
/// their menu.
class MemberProfile {
  final List<MemberSlot> slots;
  final Map<String, MacroPoints> budgets;
  final Map<String, double> fibre;
  final DietProfile? diet;
  final bool allowEdits;

  /// The colour the member chose for themselves (ARGB), or null for an
  /// automatic one.
  final int? color;

  const MemberProfile({
    this.slots = const [],
    this.budgets = const {},
    this.fibre = const {},
    this.diet,
    this.allowEdits = true,
    this.color,
  });

  MemberSlot? slot(String id) => slots.where((s) => s.id == id).firstOrNull;

  Map<String, dynamic> toJson() => {
    'slots': [for (final s in slots) s.toJson()],
    'budgets': {for (final e in budgets.entries) e.key: macroToJson(e.value)},
    'fibre': fibre,
    if (diet != null) 'diet': diet!.toJson(),
    'allowEdits': allowEdits,
    if (color != null) 'color': color,
  };

  static MemberProfile? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawBudgets = json['budgets'];
    final rawFibre = json['fibre'];
    final rawSlots = json['slots'];
    return MemberProfile(
      slots: [
        if (rawSlots is List) ...rawSlots.map(MemberSlot.fromJson).nonNulls,
      ],
      budgets: {
        if (rawBudgets is Map)
          for (final e in rawBudgets.entries)
            if (e.key is String && macroFromJson(e.value) != null)
              e.key as String: macroFromJson(e.value)!,
      },
      fibre: {
        if (rawFibre is Map)
          for (final e in rawFibre.entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toDouble(),
      },
      diet: json['diet'] == null ? null : DietProfile.fromJson(json['diet']),
      allowEdits: json['allowEdits'] != false,
      color: json['color'] is int ? json['color'] as int : null,
    );
  }

  static Map<String, double> macroToJson(MacroPoints p) => {
    'c': p.carbs,
    'p': p.protein,
    'f': p.fat,
  };

  static MacroPoints? macroFromJson(Object? json) {
    if (json is! Map) return null;
    double v(String k) => (json[k] as num?)?.toDouble() ?? 0;
    return MacroPoints(carbs: v('c'), protein: v('p'), fat: v('f'));
  }
}

/// A change one member makes to another member's meal: the foods it
/// should have. The other member's phone applies it to their menu and
/// says so, and the change is then dropped.
class MenuEdit {
  final String id;

  /// Whose menu it changes.
  final String memberId;
  final DateTime date;
  final String slotId;
  final List<PlannedItem> items;

  /// Name of the member who made it, shown on the other phone.
  final String by;
  final DateTime at;

  const MenuEdit({
    required this.id,
    required this.memberId,
    required this.date,
    required this.slotId,
    required this.items,
    required this.by,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'member': memberId,
    'date': DayPlan.dateKey(date),
    'slot': slotId,
    'items': [for (final i in items) i.toJson()],
    'by': by,
    'at': at.toIso8601String(),
  };

  static MenuEdit? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final member = json['member'];
    final slot = json['slot'];
    final date = DateTime.tryParse(json['date'] as String? ?? '');
    final rawItems = json['items'];
    if (id is! String ||
        member is! String ||
        slot is! String ||
        date == null ||
        rawItems is! List) {
      return null;
    }
    return MenuEdit(
      id: id,
      memberId: member,
      date: DayPlan.dateOnly(date),
      slotId: slot,
      items: rawItems.map(PlannedItem.fromJson).nonNulls.toList(),
      by: json['by'] as String? ?? '',
      at:
          DateTime.tryParse(json['at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// [day] with this edit's foods in its meal.
  DayPlan applyTo(DayPlan day) => day.withMeal(slotId, items);
}

/// Each member's colour: the one they chose, unless an earlier member
/// already has it; else the next free one. Never two members alike.
class HouseholdColors {
  HouseholdColors._();

  static const palette = <int>[
    0xFF1E88E5, // blue
    0xFFE53935, // red
    0xFF43A047, // green
    0xFFFFB300, // amber
    0xFF8E24AA, // purple
    0xFF00ACC1, // cyan
    0xFFF4511E, // deep orange
    0xFFD81B60, // pink
    0xFF6D4C41, // brown
    0xFF3949AB, // indigo
    0xFF7CB342, // light green
    0xFF546E7A, // blue grey
  ];

  static int _start(String memberId) {
    var hash = 0;
    for (final unit in memberId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % palette.length;
  }

  /// [picks]: each member id and the colour they chose (null: automatic).
  /// Members are settled in id order, so every phone reaches the same
  /// answer.
  static Map<String, int> resolve(Map<String, int?> picks) {
    final ids = picks.keys.toList()..sort();
    final used = <int>{};
    final out = <String, int>{};
    // Chosen colours first, then the automatic ones fill what is left.
    for (final id in ids) {
      final pick = picks[id];
      if (pick != null && !used.contains(pick)) {
        out[id] = pick;
        used.add(pick);
      }
    }
    for (final id in ids) {
      if (out.containsKey(id)) continue;
      final start = _start(id);
      for (var i = 0; i < palette.length; i++) {
        final c = palette[(start + i) % palette.length];
        if (!used.contains(c)) {
          out[id] = c;
          used.add(c);
          break;
        }
      }
      out[id] ??= palette[start];
    }
    return out;
  }
}
