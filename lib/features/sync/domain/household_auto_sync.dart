import 'dart:async';

import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/sync/data/household_store.dart';
import 'package:opennutritracker/features/sync/domain/household_sync_service.dart';

/// Keeps a shared household in step while a screen that shows shared data
/// (the weekly menu, the shopping list) is open: syncs when it opens, every
/// [interval] while it stays open, and a few seconds after a local change.
///
/// Screens call [attach] in initState and [detach] in dispose. Does nothing
/// when no household is set up or the services are not registered.
class HouseholdAutoSync {
  static final instance = HouseholdAutoSync._();

  static const interval = Duration(seconds: 30);
  static const debounce = Duration(seconds: 3);

  final _log = Logger('HouseholdAutoSync');
  int _attached = 0;
  Timer? _periodic;
  Timer? _debounced;
  bool _listening = false;

  HouseholdAutoSync._();

  bool get _available =>
      locator.isRegistered<HouseholdSyncService>() &&
      locator.isRegistered<HouseholdStore>() &&
      locator<HouseholdStore>().getHousehold() != null;

  void attach() {
    _attached++;
    if (_attached == 1) {
      _periodic = Timer.periodic(interval, (_) => syncSoon(Duration.zero));
      if (!_listening && locator.isRegistered<PlannerDataSource>()) {
        locator<PlannerDataSource>().revision.addListener(_onLocalChange);
        _listening = true;
      }
    }
    syncSoon(Duration.zero);
  }

  void detach() {
    if (_attached == 0) return;
    _attached--;
    if (_attached == 0) {
      _periodic?.cancel();
      _periodic = null;
      _debounced?.cancel();
      if (_listening) {
        locator<PlannerDataSource>().revision.removeListener(_onLocalChange);
        _listening = false;
      }
    }
  }

  bool _merging = false;

  void _onLocalChange() {
    // A merge written by the sync itself must not schedule another round.
    if (_merging) return;
    syncSoon(debounce);
  }

  void syncSoon(Duration delay) {
    _debounced?.cancel();
    _debounced = Timer(delay, _run);
  }

  Future<void> _run() async {
    try {
      if (!_available) return;
      _merging = true;
      await locator<HouseholdSyncService>().syncNow();
    } catch (e) {
      _log.fine('Background sync skipped: $e');
    } finally {
      _merging = false;
    }
  }
}
