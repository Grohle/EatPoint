import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// "Let the household change my menu": on by default. Off, the others can
/// still see the menu but not change it, and this member's points and
/// diet aren't shared. Shows nothing outside a household.
class HouseholdEditsSwitch extends StatelessWidget {
  final HouseholdStore? store;
  final EdgeInsetsGeometry? contentPadding;

  const HouseholdEditsSwitch({super.key, this.store, this.contentPadding});

  @override
  Widget build(BuildContext context) {
    final households =
        store ??
        (locator.isRegistered<HouseholdStore>()
            ? locator<HouseholdStore>()
            : null);
    if (households == null) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: households.revision,
      builder: (context, _, _) {
        if (households.getHousehold() == null) return const SizedBox.shrink();
        final s = S.of(context);
        return Semantics(
          identifier: 'household-allow-edits',
          child: SwitchListTile(
            contentPadding: contentPadding,
            secondary: const Icon(Icons.edit_calendar_rounded),
            title: Text(s.householdAllowEdits),
            subtitle: Text(s.householdAllowEditsHint),
            value: households.allowEdits,
            onChanged: households.setAllowEdits,
          ),
        );
      },
    );
  }
}
