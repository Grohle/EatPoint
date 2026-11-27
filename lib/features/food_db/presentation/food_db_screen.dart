import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/food_db/data/food_db_service.dart';
import 'package:opennutritracker/features/food_db/domain/food_database.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings → Food database: download, update or remove EatPoint's food
/// database, and its sources and licences.
class FoodDbScreen extends StatefulWidget {
  const FoodDbScreen({super.key});

  @override
  State<FoodDbScreen> createState() => _FoodDbScreenState();
}

class _FoodDbScreenState extends State<FoodDbScreen> {
  final _service = locator<FoodDbService>();
  FoodDbInfo? _latest;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // The size of the download and whether there is an update, quietly.
    _service.fetchManifest().then((latest) {
      if (mounted) setState(() => _latest = latest);
    }, onError: (_) {});
  }

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';

  Future<void> _download() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.download();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            s.foodDbDone('${FoodDatabase.instance?.foods.length ?? 0}'),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.foodDbFailed)));
    }
    if (mounted) setState(() {});
  }

  Future<void> _check() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    try {
      final latest = await _service.fetchManifest();
      final installed = _service.installed;
      final update =
          installed == null ||
          latest.version > installed.version ||
          latest.sha256 != installed.sha256;
      setState(() => _latest = latest);
      messenger.showSnackBar(
        SnackBar(
          content: Text(update ? s.foodDbUpdateAvailable : s.foodDbUpToDate),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.foodDbFailed)));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _delete() async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.foodDbDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.foodDbDelete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.delete();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.foodDbTitle)),
      body: ValueListenableBuilder<FoodDbState>(
        valueListenable: _service.state,
        builder: (context, state, _) {
          final installed = _service.installed;
          final ready = state == FoodDbState.ready && installed != null;
          final busy = state == FoodDbState.downloading;
          final latest = _latest;
          final hasUpdate =
              ready &&
              latest != null &&
              (latest.version > installed.version ||
                  latest.sha256 != installed.sha256);
          final sources = (installed ?? latest)?.sources ?? const [];
          return ListView(
            padding: const EdgeInsets.all(Dimens.spacing16),
            children: [
              Text(s.foodDbIntro, style: theme.textTheme.bodyMedium),
              const SizedBox(height: Dimens.spacing16),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    ready
                        ? Icons.check_circle_rounded
                        : Icons.cloud_download_outlined,
                    color: ready ? theme.colorScheme.primary : null,
                  ),
                  title: Text(s.foodDbTitle),
                  subtitle: Text(
                    ready
                        ? s.foodDbInstalled(
                            '${FoodDatabase.instance?.foods.length ?? installed.count}',
                            '${installed.version}',
                            installed.generated ?? '',
                          )
                        : s.foodDbNotDownloaded,
                  ),
                ),
              ),
              const SizedBox(height: Dimens.spacing16),
              if (busy)
                ValueListenableBuilder<double?>(
                  valueListenable: _service.progress,
                  builder: (context, value, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.foodDbDownloading),
                      const SizedBox(height: Dimens.spacing8),
                      LinearProgressIndicator(value: value),
                    ],
                  ),
                )
              else if (!ready || hasUpdate)
                Semantics(
                  identifier: 'food-db-download',
                  child: FilledButton.icon(
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      hasUpdate
                          ? s.foodDbUpdate
                          : latest != null
                          ? s.foodDbDownloadSize(_size(latest.bytes))
                          : s.foodDbDownload,
                    ),
                    onPressed: _download,
                  ),
                ),
              if (ready && !busy) ...[
                const SizedBox(height: Dimens.spacing8),
                OutlinedButton.icon(
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(s.foodDbCheck),
                  onPressed: _checking ? null : _check,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(s.foodDbDelete),
                  onPressed: _delete,
                ),
              ],
              if (sources.isNotEmpty) ...[
                const Divider(height: Dimens.spacing32),
                Text(s.foodDbSourcesTitle, style: theme.textTheme.titleSmall),
                for (final source in sources)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(source.name),
                    subtitle: Text(source.license),
                    trailing: source.url.isEmpty
                        ? null
                        : const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: source.url.isEmpty
                        ? null
                        : () => launchUrl(
                            Uri.parse(source.url),
                            mode: LaunchMode.externalApplication,
                          ),
                  ),
                Text(
                  s.foodDbSourcesNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
