import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household_menu.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// "Your colour": the household palette, with the colours other members
/// have marked with their initial and not selectable.
class MemberColorPicker extends StatelessWidget {
  final HouseholdStore store;

  const MemberColorPicker({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final household = store.getHousehold();
    if (household == null) return const SizedBox.shrink();
    final colors = store.memberColors();
    final mine = colors[household.memberId];
    final names = {for (final m in store.otherMembers()) m.memberId: m.name};
    final takenBy = {
      for (final e in colors.entries)
        if (e.key != household.memberId) e.value: names[e.key] ?? '',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.householdYourColor,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: Dimens.spacing4),
        Text(
          s.householdYourColorHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: Dimens.spacing8),
        Wrap(
          spacing: Dimens.spacing8,
          runSpacing: Dimens.spacing8,
          children: [
            for (final c in HouseholdColors.palette)
              Semantics(
                identifier: 'household-color-${c.toRadixString(16)}',
                selected: c == mine,
                button: takenBy[c] == null,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: takenBy.containsKey(c) || c == mine
                      ? null
                      : () => store.setMyColor(c),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(
                      c,
                    ).withValues(alpha: takenBy.containsKey(c) ? 0.35 : 1),
                    child: c == mine
                        ? const Icon(Icons.check_rounded, color: Colors.white)
                        : takenBy.containsKey(c)
                        ? Text(
                            _initial(takenBy[c]!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String _initial(String name) =>
    name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
