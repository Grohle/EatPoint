import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/features/travel/domain/travel_mode.dart';
import 'package:opennutritracker/features/travel/presentation/travel_mode_actions.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Opens the quick "Start a trip" sheet from Home.
Future<void> showTravelModeSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(0, 0, 0, Dimens.spacing16),
        child: TravelModeForm(asSheet: true),
      ),
    );

/// Settings → Travel mode.
class TravelModeScreen extends StatelessWidget {
  const TravelModeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.of(context).travelTitle)),
    body: const SingleChildScrollView(child: TravelModeForm()),
  );
}

/// The travel mode switch, the trip's last day and what it pauses.
///
/// In the sheet ([asSheet]) nothing is saved until "Start trip"; on the
/// settings screen every change is saved straight away.
class TravelModeForm extends StatefulWidget {
  final bool asSheet;

  const TravelModeForm({super.key, this.asSheet = false});

  @override
  State<TravelModeForm> createState() => _TravelModeFormState();
}

class _TravelModeFormState extends State<TravelModeForm> {
  final _store = locator<TravelModeStore>();
  late TravelMode _mode = _initial();

  TravelMode _initial() {
    final current = _store.current();
    // The sheet always prepares a trip that starts now.
    return widget.asSheet ? current.copyWith(enabled: true) : current;
  }

  Future<void> _change(TravelMode next) async {
    setState(() => _mode = next);
    if (!widget.asSheet) await TravelModeActions.apply(context, next);
  }

  Future<void> _pickUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _mode.until ?? now.add(const Duration(days: 6)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    await _change(_mode.copyWith(until: () => picked));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final until = _mode.until;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16,
            Dimens.spacing8,
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(
                  0xFFFFB300,
                ).withValues(alpha: 0.25),
                child: const Icon(Icons.flight_takeoff_rounded),
              ),
              const SizedBox(width: Dimens.spacing12),
              Expanded(
                child: Text(
                  widget.asSheet ? s.travelSheetTitle : s.travelTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
          child: Text(
            s.travelIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (!widget.asSheet)
          Semantics(
            identifier: 'travel-mode-switch',
            child: SwitchListTile(
              title: Text(s.travelSwitch),
              value: _mode.enabled,
              onChanged: (v) => _change(
                _mode.copyWith(
                  enabled: v,
                  since: v ? () => DateTime.now() : null,
                ),
              ),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.event_rounded),
          title: Text(s.travelUntilLabel),
          subtitle: Text(
            until == null
                ? s.travelUntilNone
                : DateFormat.yMMMEd(locale).format(until),
          ),
          trailing: until == null
              ? null
              : IconButton(
                  tooltip: s.travelUntilClear,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => _change(_mode.copyWith(until: () => null)),
                ),
          onTap: _pickUntil,
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing4,
            Dimens.spacing16,
            0,
          ),
          child: Text(s.travelPausesTitle, style: theme.textTheme.titleSmall),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.calendar_month_outlined),
          title: Text(s.travelPausePlanner),
          subtitle: Text(s.travelPausePlannerHelp),
          value: _mode.pausePlanner,
          onChanged: (v) => _change(_mode.copyWith(pausePlanner: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_paused_outlined),
          title: Text(s.travelPauseReminders),
          value: _mode.pauseReminders,
          onChanged: (v) => _change(_mode.copyWith(pauseReminders: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.donut_large_rounded),
          title: Text(s.travelDailyOnly),
          subtitle: Text(s.travelDailyOnlyHelp),
          value: _mode.dailyBudgetOnly,
          onChanged: (v) => _change(_mode.copyWith(dailyBudgetOnly: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.sync_disabled_rounded),
          title: Text(s.travelPauseSync),
          subtitle: Text(s.travelPauseSyncHelp),
          value: _mode.pauseHouseholdSync,
          onChanged: (v) => _change(_mode.copyWith(pauseHouseholdSync: v)),
        ),
        if (widget.asSheet)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing16,
              Dimens.spacing8,
              Dimens.spacing16,
              0,
            ),
            child: Semantics(
              identifier: 'travel-mode-start',
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(Dimens.minTouchTarget),
                ),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await TravelModeActions.apply(
                    context,
                    _mode.copyWith(enabled: true, since: () => DateTime.now()),
                  );
                  navigator.pop();
                },
                icon: const Icon(Icons.flight_takeoff_rounded),
                label: Text(s.travelStart),
              ),
            ),
          ),
      ],
    );
  }
}
