import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/planner/data/planner_reminder_service.dart';
import 'package:opennutritracker/features/planner/domain/entity/planner_entities.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The localised notification texts of the planner, resolved from [context].
PlannerReminderTexts plannerReminderTextsOf(BuildContext context) {
  final s = S.of(context);
  return PlannerReminderTexts(
    channelName: s.remindersChannelName,
    channelDescription: s.remindersChannelDescription,
    planWeekTitle: s.remindersPlanWeek,
    planWeekBody: s.remindersPlanWeekBody,
    shoppingTitle: s.remindersShopping,
    shoppingBody: s.remindersShoppingBody,
    prepareTitle: s.remindersPrepare,
    prepareBody: s.remindersPrepareBody,
    logTitle: s.remindersLog,
    logBody: s.remindersLogBody,
    mealName: (type) => mealTypeLabel(context, type),
  );
}

typedef _Weekly = ({int weekday, int hour, int minute});

/// Turns the planner's local reminders on and off and sets their times.
class PlannerRemindersScreen extends StatefulWidget {
  const PlannerRemindersScreen({super.key});

  @override
  State<PlannerRemindersScreen> createState() => _PlannerRemindersScreenState();
}

class _PlannerRemindersScreenState extends State<PlannerRemindersScreen> {
  static const _logChoices = [15, 30, 60];

  final _source = locator<PlannerDataSource>();
  late PlannerReminderSettings _settings = _source.getReminders();

  String _weekday(int weekday) {
    final locale = Localizations.localeOf(context).toString();
    // 2024-01-01 is a Monday.
    return DateFormat.EEEE(locale).format(DateTime(2024, 1, weekday));
  }

  String _time(int hour, int minute) => MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay(hour: hour, minute: minute));

  String _weeklyText(_Weekly w) =>
      '${_weekday(w.weekday)} · ${_time(w.hour, w.minute)}';

  Future<void> _apply(PlannerReminderSettings next) async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final texts = plannerReminderTextsOf(context);
    setState(() => _settings = next);
    await _source.saveReminders(next);
    final anyOn =
        next.planWeek != null ||
        next.shopping != null ||
        next.prepare != null ||
        next.logAfterMinutes != null;
    if (anyOn) {
      final granted = await locator<NotificationService>().requestPermission();
      if (!granted && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(s.notificationsPermissionDeniedSnack)),
        );
      }
    }
    final today = DayPlan.dateOnly(DateTime.now());
    await locator<PlannerReminderService>().reschedule(
      settings: next,
      upcoming: [
        for (var i = 0; i < 7; i++)
          _source.getDay(DateTime(today.year, today.month, today.day + i)),
      ],
      texts: texts,
    );
  }

  Future<_Weekly?> _pickWeekly(_Weekly initial) async {
    var weekday = initial.weekday;
    var time = TimeOfDay(hour: initial.hour, minute: initial.minute);
    return showDialog<_Weekly>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                identifier: 'reminders-weekday',
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: weekday,
                  items: [
                    for (var d = 1; d <= 7; d++)
                      DropdownMenuItem(value: d, child: Text(_weekday(d))),
                  ],
                  onChanged: (v) => setLocal(() => weekday = v ?? weekday),
                ),
              ),
              const SizedBox(height: Dimens.spacing12),
              Semantics(
                identifier: 'reminders-time',
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text(_time(time.hour, time.minute)),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: time,
                    );
                    if (picked != null) setLocal(() => time = picked);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, (
                weekday: weekday,
                hour: time.hour,
                minute: time.minute,
              )),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPlanWeek() async {
    final current = _settings.planWeek;
    if (current == null) return;
    final picked = await _pickWeekly(current);
    if (picked == null || !mounted) return;
    await _apply(_copy(planWeek: () => picked));
  }

  Future<void> _editShopping() async {
    final current = _settings.shopping;
    if (current == null) return;
    final picked = await _pickWeekly(current);
    if (picked == null || !mounted) return;
    await _apply(_copy(shopping: () => picked));
  }

  Future<void> _editPrepare() async {
    final current = _settings.prepare;
    if (current == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null || !mounted) return;
    await _apply(
      _copy(prepare: () => (hour: picked.hour, minute: picked.minute)),
    );
  }

  Future<void> _editLog() async {
    final current = _settings.logAfterMinutes;
    if (current == null) return;
    final s = S.of(context);
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(s.remindersLog),
        children: [
          for (final m in _logChoices)
            Semantics(
              identifier: 'reminders-log-$m',
              child: SimpleDialogOption(
                onPressed: () => Navigator.pop(context, m),
                child: Text(s.remindersLogSubtitle(m.toString())),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await _apply(_copy(logAfterMinutes: () => picked));
  }

  PlannerReminderSettings _copy({
    _Weekly? Function()? planWeek,
    _Weekly? Function()? shopping,
    ({int hour, int minute})? Function()? prepare,
    int? Function()? logAfterMinutes,
  }) => PlannerReminderSettings(
    planWeek: planWeek != null ? planWeek() : _settings.planWeek,
    shopping: shopping != null ? shopping() : _settings.shopping,
    prepare: prepare != null ? prepare() : _settings.prepare,
    logAfterMinutes: logAfterMinutes != null
        ? logAfterMinutes()
        : _settings.logAfterMinutes,
  );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final st = _settings;

    Widget row({
      required String id,
      required String title,
      required String? subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
      required VoidCallback onEdit,
    }) {
      return Semantics(
        identifier: id,
        container: true,
        child: InkWell(
          onTap: value ? onEdit : () => onChanged(true),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing16,
                vertical: Dimens.spacing8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Dimens.spacing8),
                  Switch(value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.plannerReminders,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: Text(
              s.remindersOffNote,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          row(
            id: 'reminders-plan-week',
            title: s.remindersPlanWeek,
            subtitle: st.planWeek == null ? null : _weeklyText(st.planWeek!),
            value: st.planWeek != null,
            onChanged: (on) => _apply(
              _copy(
                planWeek: () =>
                    on ? PlannerReminderSettings.suggestedPlanWeek : null,
              ),
            ),
            onEdit: _editPlanWeek,
          ),
          row(
            id: 'reminders-shopping',
            title: s.remindersShopping,
            subtitle: st.shopping == null ? null : _weeklyText(st.shopping!),
            value: st.shopping != null,
            onChanged: (on) => _apply(
              _copy(
                shopping: () =>
                    on ? PlannerReminderSettings.suggestedShopping : null,
              ),
            ),
            onEdit: _editShopping,
          ),
          row(
            id: 'reminders-prepare',
            title: s.remindersPrepare,
            subtitle: st.prepare == null
                ? null
                : _time(st.prepare!.hour, st.prepare!.minute),
            value: st.prepare != null,
            onChanged: (on) => _apply(
              _copy(
                prepare: () =>
                    on ? PlannerReminderSettings.suggestedPrepare : null,
              ),
            ),
            onEdit: _editPrepare,
          ),
          row(
            id: 'reminders-log',
            title: s.remindersLog,
            subtitle: s.remindersLogSubtitle(
              (st.logAfterMinutes ??
                      PlannerReminderSettings.suggestedLogAfterMinutes)
                  .toString(),
            ),
            value: st.logAfterMinutes != null,
            onChanged: (on) => _apply(
              _copy(
                logAfterMinutes: () => on
                    ? PlannerReminderSettings.suggestedLogAfterMinutes
                    : null,
              ),
            ),
            onEdit: _editLog,
          ),
        ],
      ),
    );
  }
}
