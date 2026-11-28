import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/travel/data/travel_mode_store.dart';
import 'package:opennutritracker/features/travel/domain/travel_mode.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../points/points_test_support.dart';

void main() {
  group('TravelMode', () {
    test('off is never active', () {
      expect(TravelMode.off.isActiveAt(DateTime(2024, 1, 1)), isFalse);
      expect(TravelMode.off.hasExpiredAt(DateTime(2024, 1, 1)), isFalse);
    });

    test('enabled without until is always active', () {
      const m = TravelMode(enabled: true);
      expect(m.isActiveAt(DateTime(2100)), isTrue);
      expect(m.hasExpiredAt(DateTime(2100)), isFalse);
    });

    test('until is inclusive and ends at midnight after', () {
      final m = TravelMode(enabled: true, until: DateTime(2024, 5, 10));
      expect(m.isActiveAt(DateTime(2024, 5, 9)), isTrue);
      expect(m.isActiveAt(DateTime(2024, 5, 10)), isTrue);
      expect(m.isActiveAt(DateTime(2024, 5, 10, 23, 59, 59)), isTrue);
      expect(m.isActiveAt(DateTime(2024, 5, 11)), isFalse);
      expect(m.hasExpiredAt(DateTime(2024, 5, 11)), isTrue);
      expect(m.hasExpiredAt(DateTime(2024, 5, 10, 23)), isFalse);
    });

    test('until with a time of day still counts the whole day', () {
      final m = TravelMode(enabled: true, until: DateTime(2024, 5, 10, 8));
      expect(m.isActiveAt(DateTime(2024, 5, 10, 20)), isTrue);
    });

    test('until at end of month rolls over', () {
      final m = TravelMode(enabled: true, until: DateTime(2024, 1, 31));
      expect(m.isActiveAt(DateTime(2024, 1, 31, 12)), isTrue);
      expect(m.isActiveAt(DateTime(2024, 2, 1)), isFalse);
    });

    test('disabled with until is neither active nor expired', () {
      final m = TravelMode(until: DateTime(2020));
      expect(m.isActiveAt(DateTime(2024)), isFalse);
      expect(m.hasExpiredAt(DateTime(2024)), isFalse);
    });

    test('defaults', () {
      const m = TravelMode();
      expect(m.enabled, isFalse);
      expect(m.pausePlanner, isTrue);
      expect(m.pauseReminders, isTrue);
      expect(m.pauseHouseholdSync, isFalse);
      expect(m.dailyBudgetOnly, isTrue);
    });

    test('JSON round trip', () {
      final m = TravelMode(
        enabled: true,
        until: DateTime(2024, 5, 10),
        since: DateTime(2024, 5, 1, 8, 30),
        pausePlanner: false,
        pauseReminders: false,
        pauseHouseholdSync: true,
        dailyBudgetOnly: false,
      );
      final json = jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>;
      expect(json['until'], '2024-05-10');
      final back = TravelMode.fromJson(json);
      expect(back.enabled, isTrue);
      expect(back.until, DateTime(2024, 5, 10));
      expect(back.since, DateTime(2024, 5, 1, 8, 30));
      expect(back.pausePlanner, isFalse);
      expect(back.pauseReminders, isFalse);
      expect(back.pauseHouseholdSync, isTrue);
      expect(back.dailyBudgetOnly, isFalse);
    });

    test('fromJson falls back to defaults on junk', () {
      final m = TravelMode.fromJson({
        'enabled': 'yes',
        'until': 5,
        'since': 'not a date',
        'pausePlanner': null,
      });
      expect(m.enabled, isFalse);
      expect(m.until, isNull);
      expect(m.since, isNull);
      expect(m.pausePlanner, isTrue);
      expect(m.pauseHouseholdSync, isFalse);
      expect(TravelMode.fromJson({}).dailyBudgetOnly, isTrue);
    });

    test('null until/since are omitted from JSON', () {
      final json = const TravelMode(enabled: true).toJson();
      expect(json.containsKey('until'), isFalse);
      expect(json.containsKey('since'), isFalse);
    });

    test('copyWith can clear until', () {
      final m = TravelMode(enabled: true, until: DateTime(2024));
      expect(m.copyWith(until: () => null).until, isNull);
      expect(m.copyWith().until, DateTime(2024));
    });
  });

  group('TravelModeStore', () {
    late MemoryStringBox box;
    late TravelModeStore store;
    final now = DateTime(2024, 5, 5, 10);

    setUp(() {
      box = MemoryStringBox();
      store = TravelModeStore(FakeHiveDBProvider(pointsSettingsBox: box));
    });

    test('empty store is off', () {
      expect(store.get().enabled, isFalse);
      expect(store.current(now: now).enabled, isFalse);
      expect(store.isActive(now: now), isFalse);
    });

    test('unreadable data is off', () {
      box.data['travel'] = '{oops';
      expect(store.get().enabled, isFalse);
    });

    test('setEnabled(true) turns on and stamps since', () async {
      final rev = store.revision.value;
      await store.setEnabled(true, now: now);
      expect(store.revision.value, rev + 1);
      expect(store.get().enabled, isTrue);
      expect(store.get().since, now);
      expect(store.isActive(now: now), isTrue);
    });

    test(
      'setEnabled(false) turns off (since is kept as last-on time)',
      () async {
        await store.setEnabled(true, now: now);
        await store.setEnabled(false, now: now);
        expect(store.get().enabled, isFalse);
        // copyWith(since: null) keeps the old value, so since stays.
        expect(store.get().since, now);
      },
    );

    test('current treats an expired trip as off', () async {
      await store.save(TravelMode(enabled: true, until: DateTime(2024, 5, 4)));
      expect(store.get().enabled, isTrue);
      expect(store.current(now: now).enabled, isFalse);
      expect(store.isActive(now: now), isFalse);
      expect(store.isActive(now: DateTime(2024, 5, 4, 23)), isTrue);
    });

    test('endIfExpired ends an expired trip once', () async {
      await store.save(TravelMode(enabled: true, until: DateTime(2024, 5, 4)));
      expect(await store.endIfExpired(now: now), isTrue);
      expect(store.get().enabled, isFalse);
      expect(store.get().until, isNull);
      expect(await store.endIfExpired(now: now), isFalse);
    });

    test('endIfExpired leaves a running trip alone', () async {
      await store.save(TravelMode(enabled: true, until: DateTime(2024, 5, 5)));
      expect(await store.endIfExpired(now: now), isFalse);
      expect(store.get().enabled, isTrue);
      await store.save(const TravelMode(enabled: true));
      expect(await store.endIfExpired(now: DateTime(2100)), isFalse);
    });

    test(
      'setEnabled(true) over an expired trip starts without old until',
      () async {
        await store.save(
          TravelMode(enabled: true, until: DateTime(2024, 5, 4)),
        );
        await store.setEnabled(true, now: now);
        expect(store.get().until, isNull);
        expect(store.isActive(now: now), isTrue);
      },
    );

    test('setEnabled keeps other settings', () async {
      await store.save(const TravelMode(pauseHouseholdSync: true));
      await store.setEnabled(true, now: now);
      expect(store.get().pauseHouseholdSync, isTrue);
    });
  });

  test('a trip planned ahead waits for its first day', () {
    final m = TravelMode(
      enabled: true,
      from: DateTime(2030, 6, 10),
      until: DateTime(2030, 6, 12),
    );
    expect(m.isActiveAt(DateTime(2030, 6, 9, 23)), isFalse);
    expect(m.hasExpiredAt(DateTime(2030, 6, 9)), isFalse);
    expect(m.isActiveAt(DateTime(2030, 6, 10)), isTrue);
    expect(m.isActiveAt(DateTime(2030, 6, 12, 22)), isTrue);
    expect(m.hasExpiredAt(DateTime(2030, 6, 13)), isTrue);
    final back = TravelMode.fromJson(m.toJson());
    expect(back.from, DateTime(2030, 6, 10));
  });
}
