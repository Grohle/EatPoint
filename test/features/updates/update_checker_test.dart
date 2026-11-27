import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/updates/data/update_checker.dart';
import 'package:opennutritracker/features/updates/data/update_store.dart';
import 'package:opennutritracker/features/updates/domain/app_update.dart';

import '../../features/points/points_test_support.dart';
import '../../helpers/fake_hive_db_provider.dart';

Map<String, Object?> _release(
  String tag, {
  bool draft = false,
  List<String> apks = const [],
}) => {
  'tag_name': tag,
  'draft': draft,
  'html_url': 'https://github.com/Grohle/EatPoint/releases/tag/$tag',
  'body': '## What\'s new\n- Something',
  'assets': [
    for (final name in apks)
      {
        'name': name,
        'browser_download_url':
            'https://github.com/Grohle/EatPoint/releases/download/$tag/$name',
      },
  ],
};

UpdateChecker _checker(List<Object?> releases, {int status = 200}) =>
    UpdateChecker(
      MockClient((request) async {
        expect(request.url, UpdateChecker.releasesUrl);
        return http.Response(jsonEncode(releases), status);
      }),
    );

void main() {
  test('versions compare by number, ignoring v, build and suffix', () {
    final v = AppVersion.tryParse;
    expect(v('v0.3.10')! > v('0.3.9')!, isTrue);
    expect(v('0.4')! > v('0.3.2+6')!, isTrue);
    expect(v('0.3.2+6')!.compareTo(v('v0.3.2')!), 0);
    expect(v('1.0.0-beta')!.toString(), '1.0.0');
    expect(v('latest'), isNull);
  });

  test('offers the newest release and the APK for this phone', () async {
    final checker = _checker([
      _release('v0.3.3', apks: ['EatPoint-0.3.3-arm64-v8a.apk']),
      _release(
        'v0.3.4',
        apks: [
          'EatPoint-0.3.4-arm64-v8a.apk',
          'EatPoint-0.3.4-armeabi-v7a.apk',
        ],
      ),
      _release('v0.9.0', draft: true),
      _release('v0.3.1'),
    ]);
    final update = await checker.check(
      installed: '0.3.2',
      abis: const ['armeabi-v7a'],
    );
    expect(update!.version.toString(), '0.3.4');
    expect(update.downloadUrl, endsWith('EatPoint-0.3.4-armeabi-v7a.apk'));

    final arm64 = await checker.check(installed: '0.3.2');
    expect(arm64!.downloadUrl, endsWith('EatPoint-0.3.4-arm64-v8a.apk'));
  });

  test('nothing newer means up to date', () async {
    final update = await _checker([
      _release('v0.3.2'),
      _release('v0.3.1'),
    ]).check(installed: '0.3.2+6');
    expect(update, isNull);
  });

  test('a release without APKs links to its page', () async {
    final update = await _checker([
      _release('v0.4.0'),
    ]).check(installed: '0.3.2');
    expect(update!.downloadUrl, contains('/releases/tag/v0.4.0'));
  });

  test('a server error is reported, not read as up to date', () async {
    expect(
      _checker(const [], status: 403).check(installed: '0.3.2'),
      throwsA(isA<UpdateCheckException>()),
    );
  });

  test('"Later" keeps one release quiet for a day', () async {
    final store = UpdateStore(
      FakeHiveDBProvider(pointsSettingsBox: MemoryStringBox()),
    );
    expect(store.autoCheck, isTrue);
    final now = DateTime(2026, 11, 27, 22);
    expect(store.shouldOffer('0.3.3', now: now), isTrue);
    await store.markOffered('0.3.3', now: now);
    expect(
      store.shouldOffer('0.3.3', now: now.add(const Duration(hours: 5))),
      isFalse,
    );
    expect(store.shouldOffer('0.3.4', now: now), isTrue);
    expect(
      store.shouldOffer('0.3.3', now: now.add(const Duration(days: 1))),
      isTrue,
    );
    await store.setAutoCheck(false);
    expect(store.autoCheck, isFalse);
  });
}
