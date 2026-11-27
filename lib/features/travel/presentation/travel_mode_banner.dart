import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/features/travel/presentation/travel_mode_actions.dart';
import 'package:opennutritracker/features/travel/presentation/travel_mode_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Says that travel mode is on and what it pauses, with buttons to change
/// it or turn it off. Shown on Home, and on the menu and the shopping list
/// when they are opened during a trip.
class TravelModeBanner extends StatelessWidget {
  final EdgeInsetsGeometry margin;

  const TravelModeBanner({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(
      Dimens.spacing16,
      Dimens.spacing8,
      Dimens.spacing16,
      Dimens.spacing4,
    ),
  });

  @override
  Widget build(BuildContext context) {
    if (!locator.isRegistered<TravelModeStore>()) {
      return const SizedBox.shrink();
    }
    final s = S.of(context);
    final theme = Theme.of(context);
    final mode = locator<TravelModeStore>().current();
    if (!mode.enabled) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context).toString();
    final until = mode.until;
    final paused = [
      if (mode.pausePlanner) s.travelPausedMenus,
      if (mode.pauseReminders) s.travelPausedReminders,
      if (mode.pauseHouseholdSync) s.travelPausedSync,
      if (mode.dailyBudgetOnly) s.travelDailyOnlyShort,
    ];

    return Padding(
      padding: margin,
      child: Semantics(
        identifier: 'travel-mode-banner',
        container: true,
        child: Material(
          color: const Color(0xFFFFB300).withValues(alpha: 0.18),
          borderRadius: Dimens.borderRadiusL,
          child: InkWell(
            borderRadius: Dimens.borderRadiusL,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TravelModeScreen())),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing16,
                Dimens.spacing12,
                Dimens.spacing8,
                Dimens.spacing12,
              ),
              child: Row(
                children: [
                  const Icon(Icons.flight_takeoff_rounded),
                  const SizedBox(width: Dimens.spacing12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          until == null
                              ? s.travelBannerTitle
                              : s.travelBannerTitleUntil(
                                  DateFormat.MMMd(locale).format(until),
                                ),
                          style: theme.textTheme.titleSmall,
                        ),
                        if (paused.isNotEmpty)
                          Text(
                            paused.join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Semantics(
                    identifier: 'travel-mode-turn-off',
                    child: TextButton(
                      onPressed: () =>
                          TravelModeActions.setEnabled(context, false),
                      child: Text(s.travelTurnOff),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
