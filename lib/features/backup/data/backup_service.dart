import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/settings/domain/usecase/export_data_usecase.dart';
import 'package:opennutritracker/features/settings/domain/usecase/import_data_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/export_import_bloc.dart';
import 'package:opennutritracker/features/sharing/eatpoint_export.dart';

/// One file with everything worth keeping: the diary, recipes, the user's
/// own foods, weight and goals (the app's own export), plus EatPoint's
/// points, menus, shopping lists, diet, unit weights and settings.
///
/// The household membership and the other members' menus are left out:
/// they belong to the household, which a phone rejoins by invite.
class BackupService {
  static const eatPointEntry = 'eatpoint.json';

  final ExportDataUsecase _export;
  final ImportDataUsecase _import;
  final HiveDBProvider _db;

  BackupService(this._export, this._import, this._db);

  /// "eatpoint-backup-2026-11-28-0930.zip".
  static String fileName(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'eatpoint-backup-${at.year}-${two(at.month)}-${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}.zip';
  }

  /// Whether [name] is one of these backups.
  static bool isBackupName(String name) =>
      name.startsWith('eatpoint-backup-') && name.endsWith('.zip');

  Future<Uint8List> build({DateTime? now}) async {
    final archive = await _export.assembleArchive(
      format: ExportFormat.json,
      userActivityJsonFileName: ExportImportBloc.userActivityJsonFileName,
      userIntakeJsonFileName: ExportImportBloc.userIntakeJsonFileName,
      trackedDayJsonFileName: ExportImportBloc.trackedDayJsonFileName,
      recipeJsonFileName: ExportImportBloc.recipeJsonFileName,
      weightLogJsonFileName: ExportImportBloc.weightLogJsonFileName,
      customActivityTemplateJsonFileName:
          ExportImportBloc.customActivityTemplateJsonFileName,
      goalSettingsJsonFileName: ExportImportBloc.goalSettingsJsonFileName,
      favouriteJsonFileName: ExportImportBloc.favouriteJsonFileName,
    );
    final eatPoint = utf8.encode(EatPointExport(_db).exportJson(now: now));
    archive.addFile(ArchiveFile(eatPointEntry, eatPoint.length, eatPoint));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Puts a backup back, replacing what is on the phone. Also takes an
  /// EatPoint-only export (the older JSON file).
  Future<void> restore(Uint8List bytes) async {
    final text = _jsonText(bytes);
    if (text != null) {
      await EatPointExport(_db).importJson(text);
      return;
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('Not an EatPoint backup');
    }
    final eatPoint = archive.findFile(eatPointEntry);
    final hasDiary =
        archive.findFile(ExportImportBloc.userIntakeJsonFileName) != null;
    if (eatPoint == null && !hasDiary) {
      throw const FormatException('Not an EatPoint backup');
    }
    if (hasDiary) {
      await _import.importData(
        ExportImportBloc.userActivityJsonFileName,
        ExportImportBloc.userIntakeJsonFileName,
        ExportImportBloc.trackedDayJsonFileName,
        ExportImportBloc.recipeJsonFileName,
        ExportImportBloc.weightLogJsonFileName,
        ExportImportBloc.customActivityTemplateJsonFileName,
        goalSettingsJsonFileName: ExportImportBloc.goalSettingsJsonFileName,
        favouriteJsonFileName: ExportImportBloc.favouriteJsonFileName,
        fromBackup: archive,
      );
    }
    if (eatPoint != null) {
      await EatPointExport(
        _db,
      ).importJson(utf8.decode(eatPoint.content as List<int>));
    }
  }

  static String? _jsonText(Uint8List bytes) {
    final start = bytes.indexWhere((b) => b > 32);
    if (start < 0 || bytes[start] != 0x7b) return null; // '{'
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }
}
