import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';

/// A household member's colour, the same on every screen and phone: the
/// household's resolved colour for that member id, else one from [key].
Color memberColor(String key) {
  if (locator.isRegistered<HouseholdStore>()) {
    final resolved = locator<HouseholdStore>().memberColors()[key];
    if (resolved != null) return Color(resolved);
  }
  return _hashColor(key);
}

Color _hashColor(String key) {
  const colours = [
    Color(0xFFFFB300),
    Color(0xFF42A5F5),
    Color(0xFFEC407A),
    Color(0xFF26A69A),
    Color(0xFFAB47BC),
    Color(0xFFFF7043),
  ];
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return colours[hash % colours.length];
}

/// A small circle with a member's initial.
class MemberAvatar extends StatelessWidget {
  final String name;

  /// What picks the colour: the member id, or the name when there's none.
  final String colourKey;
  final double radius;

  const MemberAvatar({
    super.key,
    required this.name,
    required this.colourKey,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final colour = memberColor(colourKey);
    final onColour = colour.computeLuminance() > 0.45
        ? Colors.black87
        : Colors.white;
    return Tooltip(
      message: name,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: colour,
        child: Text(
          name.trim().isEmpty
              ? '?'
              : name.trim().characters.first.toUpperCase(),
          style: TextStyle(
            fontSize: radius * 0.95,
            fontWeight: FontWeight.w700,
            color: onColour,
          ),
        ),
      ),
    );
  }
}
