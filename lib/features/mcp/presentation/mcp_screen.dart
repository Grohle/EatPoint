import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/mcp/data/mcp_controller.dart';
import 'package:opennutritracker/features/mcp/domain/mcp_server.dart';
import 'package:opennutritracker/features/points/presentation/meal_type_label.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Settings for the agent connector: switch it on, copy the client
/// configuration and approve or reject what an agent proposed.
class McpScreen extends StatefulWidget {
  final McpController? controller;

  /// Looks up the device's LAN addresses. Defaults to
  /// [McpController.lanAddresses].
  final Future<List<String>> Function()? lanAddresses;

  const McpScreen({super.key, this.controller, this.lanAddresses});

  @override
  State<McpScreen> createState() => _McpScreenState();
}

class _McpScreenState extends State<McpScreen> {
  late final McpController _controller =
      widget.controller ?? locator<McpController>();

  List<String> _addresses = const [];
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _controller.revision.addListener(_reload);
    _loadAddresses();
  }

  @override
  void dispose() {
    _controller.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAddresses() async {
    List<String> found;
    try {
      found = await (widget.lanAddresses ?? McpController.lanAddresses)();
    } catch (_) {
      found = const [];
    }
    if (mounted) setState(() => _addresses = found);
  }

  Future<void> _setEnabled(bool value) async {
    await _controller.saveConfig(
      _controller.getConfig().copyWith(enabled: value),
    );
    await _controller.applyConfig();
    await _loadAddresses();
  }

  Future<void> _newToken() async {
    await _controller.saveConfig(
      _controller.getConfig().copyWith(token: McpServer.generateToken()),
    );
    await _controller.applyConfig();
  }

  Future<void> _copyConfig(String url, String token) async {
    await Clipboard.setData(
      ClipboardData(text: McpController.clientConfig(url, token)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).mcpCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final config = _controller.getConfig();
    final running = _controller.isRunning;
    final port = _controller.port;
    final urls = [
      if (running && port != null)
        for (final ip in _addresses) 'http://$ip:$port${McpServer.path}',
    ];
    final proposals = _controller.proposals();

    return Scaffold(
      appBar: AppBar(title: Text(s.mcpTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.mcpIntro),
          const SizedBox(height: 8),
          Semantics(
            identifier: 'mcp-enable',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.mcpEnable),
              value: config.enabled,
              onChanged: _setEnabled,
            ),
          ),
          if (running) ...[
            const SizedBox(height: 8),
            Text(s.mcpAddress, style: Theme.of(context).textTheme.titleSmall),
            if (urls.isEmpty)
              Text(s.mcpNoNetwork)
            else
              for (final url in urls) SelectableText(url),
            const SizedBox(height: 16),
            Text(s.mcpToken, style: Theme.of(context).textTheme.titleSmall),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _showToken ? config.token : '•' * 16,
                    maxLines: 1,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showToken ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (urls.isNotEmpty)
                  Semantics(
                    identifier: 'mcp-copy-config',
                    child: FilledButton.icon(
                      icon: const Icon(Icons.copy),
                      label: Text(s.mcpCopyConfig),
                      onPressed: () => _copyConfig(urls.first, config.token),
                    ),
                  ),
                Semantics(
                  identifier: 'mcp-new-token',
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: Text(s.mcpNewToken),
                    onPressed: _newToken,
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 32),
          Semantics(
            identifier: 'mcp-allow-diary',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.mcpAllowDiary),
              value: config.allowDiary,
              onChanged: (value) =>
                  _controller.saveConfig(config.copyWith(allowDiary: value)),
            ),
          ),
          const Divider(height: 32),
          Text(s.mcpProposals, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (proposals.isEmpty)
            Text(s.mcpNoProposals)
          else
            for (final p in proposals) _proposalCard(context, p),
        ],
      ),
    );
  }

  String _describe(BuildContext context, McpProposal p) {
    final s = S.of(context);
    switch (p.kind) {
      case McpProposalKind.addDish:
        final amount = (p.data['amount'] as num?)?.round() ?? 0;
        final unit = p.data['unit'] as String? ?? 'g';
        final type = IntakeTypeEntity.values.byName(p.data['meal'] as String);
        final date = DateTime.tryParse(p.data['date'] as String? ?? '');
        final locale = Localizations.localeOf(context).toString();
        return s.mcpProposalAdd(
          p.data['name'] as String? ?? '',
          '$amount $unit',
          mealTypeLabel(context, type),
          date == null ? '' : DateFormat.MMMEd(locale).format(date),
        );
      case McpProposalKind.tickItem:
        return s.mcpProposalTick(p.data['name'] as String? ?? '');
    }
  }

  Widget _proposalCard(BuildContext context, McpProposal p) {
    final s = S.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_describe(context, p)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Semantics(
                  identifier: 'mcp-reject-${p.id}',
                  child: TextButton(
                    onPressed: () => _controller.reject(p.id),
                    child: Text(s.mcpReject),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  identifier: 'mcp-approve-${p.id}',
                  child: FilledButton(
                    onPressed: () => _controller.approve(p.id),
                    child: Text(s.mcpApprove),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
