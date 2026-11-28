
import 'package:flutter/material.dart';
import 'package:opennutritracker/features/mcp/presentation/mcp_screen.dart';
import 'package:opennutritracker/features/sync/presentation/household_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/features/menu_import/presentation/menu_import_screen.dart';
import 'package:opennutritracker/features/backup/presentation/backup_screen.dart';

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
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const McpScreen())),
            ),
          ),
          const Divider(),
          Semantics(
            identifier: 'share-hub-backup',
            child: ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: Text(s.backupTitle),
              subtitle: Text(s.backupSubtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const BackupScreen())),
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
}
