import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/backup/data/backup_service.dart';
import 'package:opennutritracker/features/backup/data/backup_settings.dart';
import 'package:opennutritracker/features/settings/domain/usecase/export_data_usecase.dart';
import 'package:opennutritracker/features/settings/domain/usecase/import_data_usecase.dart';

import '../../helpers/fake_hive_db_provider.dart';
import '../points/points_test_support.dart';

class _Box extends MemoryStringBox {
  @override
  Iterable<dynamic> get keys => data.keys;

  @override
  Future<void> putAll(Map<dynamic, String> entries) async =>
      entries.forEach((k, v) => data[k as String] = v);
}

class _Export extends Fake implements ExportDataUsecase {
  @override
  Future<Archive> assembleArchive({
    required ExportFormat format,
    required String userActivityJsonFileName,
    required String userIntakeJsonFileName,
    required String trackedDayJsonFileName,
    required String recipeJsonFileName,
    required String weightLogJsonFileName,
    required String customActivityTemplateJsonFileName,
    String goalSettingsJsonFileName = 'goal_settings.json',
    String favouriteJsonFileName = 'user_favourites.json',
    String userActivityCsvFileName = 'user_activity.csv',
    String userIntakeCsvFileName = 'user_intake.csv',
    String trackedDayCsvFileName = 'user_tracked_day.csv',
  }) async {
    final bytes = utf8.encode('[]');
    return Archive()
      ..addFile(ArchiveFile(userIntakeJsonFileName, bytes.length, bytes));
  }
}

class _Import extends Fake implements ImportDataUsecase {
  Archive? restored;

  @override
  Future<bool> importData(
    String userActivityJsonFileName,
    String userIntakeJsonFileName,
    String trackedDayJsonFileName,
    String recipeJsonFileName,
    String weightLogJsonFileName,
    String customActivityTemplateJsonFileName, {
    String goalSettingsJsonFileName = 'goal_settings.json',
    String favouriteJsonFileName = 'user_favourites.json',
    Archive? fromBackup,
  }) async {
    restored = fromBackup;
    return true;
  }
}

void main() {
  test(
    'a backup carries the diary and EatPoint\'s data, and restores both',
    () async {
      final box = _Box();
      box.data['diet'] = jsonEncode({'diet': 'vegetarian'});
      box.data['household'] = jsonEncode({'secret': 'stays home'});
      final source = BackupService(
        _Export(),
        _Import(),
        FakeHiveDBProvider(pointsSettingsBox: box),
      );
      final bytes = await source.build();
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.findFile('user_intake.json'), isNotNull);
      final eatPoint = archive.findFile(BackupService.eatPointEntry)!;
      final text = utf8.decode(eatPoint.content as List<int>);
      expect(text, contains('vegetarian'));
      expect(text, isNot(contains('stays home')));

      final otherBox = _Box();
      final import = _Import();
      await BackupService(
        _Export(),
        import,
        FakeHiveDBProvider(pointsSettingsBox: otherBox),
      ).restore(bytes);
      expect(import.restored, isNotNull);
      expect(otherBox.data['diet'], contains('vegetarian'));
      expect(otherBox.data.containsKey('household'), isFalse);
    },
  );

  test('an older EatPoint export (.json) restores too', () async {
    final box = _Box();
    await BackupService(
      _Export(),
      _Import(),
      FakeHiveDBProvider(pointsSettingsBox: box),
    ).restore(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 'eatpoint-export',
            'version': 1,
            'entries': {
              'travel_x': {'a': 1},
            },
          }),
        ),
      ),
    );
    expect(box.data['travel_x'], isNotNull);
  });

  test('anything else is refused without touching the data', () async {
    final service = BackupService(
      _Export(),
      _Import(),
      FakeHiveDBProvider(pointsSettingsBox: _Box()),
    );
    expect(
      service.restore(Uint8List.fromList(utf8.encode('hello'))),
      throwsFormatException,
    );
  });

  test('automatic copies are due daily or weekly', () async {
    final settings = BackupSettings(
      FakeHiveDBProvider(pointsSettingsBox: _Box()),
    );
    final now = DateTime(2026, 11, 28, 10);
    expect(settings.due(now), isFalse);
    await settings.setAuto(AutoBackup.daily);
    expect(settings.due(now), isTrue);
    await settings.setLastAt(now.subtract(const Duration(hours: 3)));
    expect(settings.due(now), isFalse);
    await settings.setAuto(AutoBackup.weekly);
    await settings.setLastAt(now.subtract(const Duration(days: 8)));
    expect(settings.due(now), isTrue);
    expect(BackupService.fileName(now), 'eatpoint-backup-2026-11-28-1000.zip');
  });
}
