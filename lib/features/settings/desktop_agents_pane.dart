import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/agent_setup.dart';
import '../../data/agent_bridge.dart';
import '../../data/agent_clients.dart';
import '../../data/providers.dart';
import '../../shared/desktop_ui.dart';
import 'desktop_settings.dart' show DesktopSettingsBox, DesktopSettingsRow;

/// Settings › AI Agents (design frame N07d, P5-06): whether agents may
/// connect, whether metadata asks, how to set up each kind of agent, the
/// paired clients, and what they did this session.
class DesktopAgentsPane extends ConsumerWidget {
  const DesktopAgentsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final bridge = ref.watch(agentBridgeProvider);
    final supported = ref.watch(agentSocketPathProvider) != null;
    final helper =
        ref.watch(agentHelperPathProvider) ??
        '/Applications/DevVault.app/Contents/Helpers/devvault-mcp';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20,
      children: [
        DesktopSettingsBox(
          children: [
            DesktopSettingsRow(
              title: 'Allow AI agents',
              onTap: supported
                  ? () => notifier.setAgentsEnabled(!settings.agentsEnabled)
                  : null,
              description: supported
                  ? 'Claude Code and other MCP clients reach DevVault through '
                        'devvault-mcp. Every secret asks you first.'
                  : 'Available on macOS for now.',
              details: [
                if (bridge.otherInstance)
                  'Another copy of DevVault is already serving agents.',
              ],
              trailing: DesktopSwitch(
                value: supported && settings.agentsEnabled,
                onChanged: supported ? notifier.setAgentsEnabled : null,
                semanticLabel: 'Allow AI agents',
              ),
            ),
            DesktopSettingsRow(
              title: 'Keep running when the window is closed',
              onTap: supported && settings.agentsEnabled
                  ? () => notifier.setKeepRunningWhenClosed(
                      !settings.keepRunningWhenClosed,
                    )
                  : null,
              description:
                  'Closing the window locks the vault and hides DevVault, so '
                  'agents can still reach it. Click the Dock icon to bring it '
                  'back; ⌘Q quits.',
              trailing: DesktopSwitch(
                value:
                    supported &&
                    settings.agentsEnabled &&
                    settings.keepRunningWhenClosed,
                onChanged: supported && settings.agentsEnabled
                    ? notifier.setKeepRunningWhenClosed
                    : null,
                semanticLabel: 'Keep running when the window is closed',
              ),
            ),
            DesktopSettingsRow(
              title: 'Read metadata without asking',
              onTap: () => notifier.setAgentMetadataWithoutAsking(
                !settings.agentMetadataWithoutAsking,
              ),
              description:
                  'Titles, types, apps, field names and expiry dates. Never '
                  'secret values.',
              trailing: DesktopSwitch(
                value: settings.agentMetadataWithoutAsking,
                onChanged: notifier.setAgentMetadataWithoutAsking,
                semanticLabel: 'Read metadata without asking',
              ),
            ),
            _AgentSetupRow(helper: helper),
          ],
        ),
        _Clients(clients: bridge.clients),
        _Activity(activity: bridge.activity),
      ],
    );
  }
}

/// "Set up" for the agent picked in the pop-up: what to do, the snippet,
/// and Copy.
class _AgentSetupRow extends ConsumerStatefulWidget {
  const _AgentSetupRow({required this.helper});

  final String helper;

  @override
  ConsumerState<_AgentSetupRow> createState() => _AgentSetupRowState();
}

class _AgentSetupRowState extends ConsumerState<_AgentSetupRow> {
  AgentClientKind _kind = AgentClientKind.claudeCode;

  @override
  Widget build(BuildContext context) {
    final setup = agentSetupFor(_kind, widget.helper);
    final mono = AppText.mono(
      context,
      fontSize: DesktopMetrics.secondarySize,
      color: context.desktopColors.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopSettingsRow(
          title: 'Set up an agent',
          description: setup.instruction,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Semantics(
                label: 'Agent',
                child: DesktopPopup<AgentClientKind>(
                  value: _kind,
                  choices: [
                    for (final kind in AgentClientKind.values)
                      DesktopChoice(kind, kind.label),
                  ],
                  onChanged: (kind) => setState(() => _kind = kind),
                ),
              ),
              DesktopButton(
                label: 'Copy',
                icon: DesktopSymbol.copy,
                onPressed: () => ref
                    .read(clipboardGuardProvider)
                    .clipboard
                    .write(setup.snippet),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Text(setup.snippet, style: mono),
        ),
      ],
    );
  }
}

class _Clients extends ConsumerWidget {
  const _Clients({required this.clients});

  final List<PairedClient> clients;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat('d MMM y');
    return _Titled(
      title: 'Connected clients',
      child: DesktopSettingsBox(
        children: [
          if (clients.isEmpty)
            const DesktopSettingsRow(
              title: 'None yet',
              description:
                  'A client asks to connect the first time it needs DevVault.',
            ),
          for (final client in clients)
            DesktopSettingsRow(
              title: client.name,
              leading: const DesktopIcon(DesktopSymbol.agent, size: 16),
              description: [
                'Connected ${date.format(client.pairedAt.toLocal())}',
                if (client.lastSeen case final seen?)
                  'last seen ${date.format(seen.toLocal())}',
              ].join(' · '),
              trailing: DesktopButton(
                label: 'Disconnect',
                kind: DesktopButtonKind.destructive,
                onPressed: () =>
                    ref.read(agentBridgeProvider.notifier).revoke(client),
              ),
            ),
        ],
      ),
    );
  }
}

class _Activity extends StatelessWidget {
  const _Activity({required this.activity});

  final List<AgentActivity> activity;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('d MMM, HH:mm');
    return _Titled(
      title: 'Recent activity (until DevVault quits)',
      child: DesktopSettingsBox(
        children: [
          if (activity.isEmpty) const DesktopSettingsRow(title: 'Nothing yet'),
          for (final entry in activity.take(50))
            DesktopSettingsRow(
              title: '${entry.action} · ${entry.detail}',
              description:
                  '${entry.client} · ${time.format(entry.at.toLocal())} · '
                  '${entry.outcome}',
            ),
        ],
      ),
    );
  }
}

/// A box with a heading above it, like the inspector's group boxes.
class _Titled extends StatelessWidget {
  const _Titled({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 6,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          title,
          style: TextStyle(
            fontSize: DesktopMetrics.secondarySize,
            fontWeight: FontWeight.w600,
            color: context.desktopColors.secondaryText,
          ),
        ),
      ),
      child,
    ],
  );
}
