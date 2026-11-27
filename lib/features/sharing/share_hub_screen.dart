import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/mcp/presentation/mcp_screen.dart';
import 'package:opennutritracker/features/planner/data/planner_data_source.dart';
import 'package:opennutritracker/features/points/data/points_settings_data_source.dart';
import 'package:opennutritracker/features/sharing/eatpoint_export.dart';
import 'package:opennutritracker/features/sync/presentation/household_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/features/menu_import/presentation/menu_import_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// "Share and sync": the shared household and the agent connector.
class ShareHubScreen extends StatelessWidget {
  const ShareHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.householdEntry)),
      body: ListView(
        children: [
          Semantics(
            identifier: 'share-hub-household',
            child: ListTile(
              leading: const Icon(Icons.group_outlined),
              title: Text(s.householdTitle),
              subtitle: Text(s.householdStorageSupabaseSubtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HouseholdScreen()),
              ),
            ),
          ),
          Semantics(
            identifier: 'share-hub-mcp',
            child: ListTile(
              leading: const Icon(Icons.terminal_rounded),
              title: Text(s.mcpTitle),
              subtitle: Text(
                s.mcpIntro,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const McpScreen()),
              ),
            ),
          ),
          const Divider(),
          Semantics(
            identifier: 'share-hub-export',
            child: ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: Text(s.shareExportData),
              subtitle: Text(s.shareExportDataSubtitle),
              onTap: () => _export(context),
            ),
          ),
          Semantics(
            identifier: 'share-hub-import',
            child: ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(s.shareImportData),
              onTap: () => _import(context),
            ),
          ),
          Semantics(
            identifier: 'share-hub-import-menu',
            child: ListTile(
              leading: const Icon(Icons.restaurant_menu_rounded),
              title: Text(s.menuImportTitle),
              subtitle: Text(s.menuImportEntrySubtitle),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MenuImportScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final json = EatPointExport(locator<HiveDBProvider>()).exportJson();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/eatpoint-export.json');
    await file.writeAsString(json);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null) return;
    try {
      final text = utf8.decode(await picked.readAsBytes());
      final count = await EatPointExport(
        locator<HiveDBProvider>(),
      ).importJson(text);
      locator<PlannerDataSource>().revision.value++;
      locator<PointsSettingsDataSource>().revision.value++;
      messenger.showSnackBar(
        SnackBar(content: Text(s.shareImported(count.toString()))),
      );
    } on FormatException {
      messenger.showSnackBar(SnackBar(content: Text(s.shareImportInvalid)));
    }
  }
}
