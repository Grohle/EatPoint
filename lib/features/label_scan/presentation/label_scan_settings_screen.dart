import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/label_scan/presentation/label_scan_screen.dart';
import 'package:opennutritracker/features/settings/settings_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The three ways a label can be read, in the order they are tried.
class LabelScanSettingsScreen extends StatefulWidget {
  const LabelScanSettingsScreen({super.key});

  @override
  State<LabelScanSettingsScreen> createState() =>
      _LabelScanSettingsScreenState();
}

class _LabelScanSettingsScreenState extends State<LabelScanSettingsScreen> {
  AiSelection? _selection;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    AiSelection? selection;
    try {
      selection = await locator<AiCredentialStorage>().readSelection();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _selection = selection;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    Widget step(int n, {required bool active}) => CircleAvatar(
      radius: 14,
      backgroundColor: active
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHighest,
      child: Text(
        '$n',
        style: TextStyle(
          color: active
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.labelScanSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Dimens.spacing8),
        children: [
          Padding(
            padding: const EdgeInsets.all(Dimens.spacing16),
            child: Text(s.labelScanOrder, style: theme.textTheme.bodyMedium),
          ),
          ListTile(
            leading: step(1, active: true),
            title: Text(s.labelScanEngineOnDevice),
            subtitle: Text(s.labelScanEngineOnDeviceSubtitle),
          ),
          ListTile(
            enabled: false,
            leading: step(2, active: false),
            title: Text(s.labelScanEngineLocalModel),
            subtitle: Text(s.labelScanEngineLocalModelSubtitle),
            trailing: Chip(label: Text(s.labelScanInDevelopment)),
          ),
          Semantics(
            identifier: 'label-scan-settings-ai',
            child: ListTile(
              leading: step(3, active: _selection != null),
              title: Text(s.labelScanEngineAi),
              subtitle: !_loaded
                  ? null
                  : Text(
                      _selection == null
                          ? s.labelScanEngineAiOff
                          : s.labelScanEngineAiOn(
                              labelScanProviderName(_selection!),
                            ),
                    ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                await Navigator.of(context).pushNamed(
                  NavigationOptions.settingsRoute,
                  arguments: const SettingsScreenArguments(openAiAssist: true),
                );
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }
}
