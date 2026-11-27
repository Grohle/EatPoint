/// Travel mode: for days away from home, when there is no menu to follow
/// and no shopping to do. The app only logs what the user eats, against the
/// daily budget.
///
/// What it pauses is configurable. Everything comes back as it was when
/// travel mode ends, by hand or on [until].
class TravelMode {
  final bool enabled;

  /// The last day of the trip, inclusive. Null means "until I turn it off".
  final DateTime? until;

  /// When travel mode was last turned on.
  final DateTime? since;

  /// Hide the weekly menu and the shopping list.
  final bool pausePlanner;

  /// Silence the planner's reminders (plan the week, shopping, prepare,
  /// log what you planned).
  final bool pauseReminders;

  /// Stop syncing with the shared household.
  final bool pauseHouseholdSync;

  /// Count against the daily budget only, without per-meal budgets.
  final bool dailyBudgetOnly;

  const TravelMode({
    this.enabled = false,
    this.until,
    this.since,
    this.pausePlanner = true,
    this.pauseReminders = true,
    this.pauseHouseholdSync = false,
    this.dailyBudgetOnly = true,
  });

  static const off = TravelMode();

  /// Whether travel mode applies at [now]: on, and [until] not yet past.
  bool isActiveAt(DateTime now) {
    if (!enabled) return false;
    final last = until;
    if (last == null) return true;
    final endExclusive = DateTime(last.year, last.month, last.day + 1);
    return now.isBefore(endExclusive);
  }

  /// Whether travel mode is on but its last day has passed.
  bool hasExpiredAt(DateTime now) => enabled && !isActiveAt(now);

  TravelMode copyWith({
    bool? enabled,
    DateTime? Function()? until,
    DateTime? Function()? since,
    bool? pausePlanner,
    bool? pauseReminders,
    bool? pauseHouseholdSync,
    bool? dailyBudgetOnly,
  }) => TravelMode(
    enabled: enabled ?? this.enabled,
    until: until != null ? until() : this.until,
    since: since != null ? since() : this.since,
    pausePlanner: pausePlanner ?? this.pausePlanner,
    pauseReminders: pauseReminders ?? this.pauseReminders,
    pauseHouseholdSync: pauseHouseholdSync ?? this.pauseHouseholdSync,
    dailyBudgetOnly: dailyBudgetOnly ?? this.dailyBudgetOnly,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (until != null) 'until': _date(until!),
    if (since != null) 'since': since!.toIso8601String(),
    'pausePlanner': pausePlanner,
    'pauseReminders': pauseReminders,
    'pauseHouseholdSync': pauseHouseholdSync,
    'dailyBudgetOnly': dailyBudgetOnly,
  };

  factory TravelMode.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    DateTime? date(String key) =>
        json[key] is String ? DateTime.tryParse(json[key] as String) : null;
    final until = date('until');
    return TravelMode(
      enabled: flag('enabled', false),
      until: until == null
          ? null
          : DateTime(until.year, until.month, until.day),
      since: date('since'),
      pausePlanner: flag('pausePlanner', true),
      pauseReminders: flag('pauseReminders', true),
      pauseHouseholdSync: flag('pauseHouseholdSync', false),
      dailyBudgetOnly: flag('dailyBudgetOnly', true),
    );
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
