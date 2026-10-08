import 'package:agent_bridge/agent_bridge.dart' show DeliveryMode;

import '../../data/agent_bridge.dart';
import '../../shared/desktop_ui.dart';

/// Shows [prompt] as a sheet (design frame N09) and resolves with the
/// user's answer; null when the prompt closed first (the agent gave up or
/// timed out, the vault locked) or the sheet was dismissed, which counts
/// as a denial.
Future<AgentDecision?> showAgentPromptSheet(
  BuildContext context,
  AgentPrompt prompt,
) => showDesktopSheet<AgentDecision>(
  context,
  builder: (_) => AgentPromptSheet(prompt: prompt),
);

/// What an AI agent asks for, and the buttons to answer it: pairing a new
/// client, reading metadata (when that asks), or secret values with where
/// they'll go.
class AgentPromptSheet extends StatefulWidget {
  const AgentPromptSheet({super.key, required this.prompt});

  final AgentPrompt prompt;

  @override
  State<AgentPromptSheet> createState() => _AgentPromptSheetState();
}

class _AgentPromptSheetState extends State<AgentPromptSheet> {
  @override
  void initState() {
    super.initState();
    // Closes itself when the question goes away without an answer here.
    widget.prompt.closed.then((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  void _answer(AgentDecision decision) => Navigator.of(context).pop(decision);

  @override
  Widget build(BuildContext context) {
    final prompt = widget.prompt;
    final client = '“${prompt.client}”';
    final icon = DesktopIcon(
      DesktopSymbol.agent,
      size: 28,
      color: context.desktopColors.accentIcon,
    );
    return switch (prompt) {
      PairPrompt() => DesktopSheet(
        icon: icon,
        title: '$client wants to connect to DevVault',
        message:
            'It will see your items’ titles, types, apps and expiry dates, '
            'and can ask you for secrets. Every secret still asks first.',
        actions: [
          DesktopButton(
            label: 'Don’t Allow',
            onPressed: () => _answer(AgentDecision.deny),
          ),
          DesktopButton(
            label: 'Allow',
            kind: DesktopButtonKind.primary,
            onPressed: () => _answer(AgentDecision.allowOnce),
          ),
        ],
        child: const SizedBox.shrink(),
      ),
      MetadataPrompt(:final what) => DesktopSheet(
        icon: icon,
        title: '$client wants to read $what',
        message:
            'Titles, types, apps, field names and expiry dates. Never secret '
            'values.',
        actions: _allowActions(),
        child: const SizedBox.shrink(),
      ),
      SecretPrompt() => DesktopSheet(
        icon: icon,
        width: 560,
        title: switch (prompt.delivery.mode) {
          DeliveryMode.reveal => '$client wants to see secrets',
          DeliveryMode.file => '$client wants to write secrets to a file',
          DeliveryMode.command => '$client wants to run a command with secrets',
        },
        message: 'Nothing leaves DevVault unless you allow it.',
        actions: _allowActions(),
        child: _SecretDetails(prompt: prompt),
      ),
    };
  }

  List<Widget> _allowActions() => [
    DesktopButton(label: 'Deny', onPressed: () => _answer(AgentDecision.deny)),
    DesktopButton(
      label: 'Allow for 15 Minutes',
      onPressed: () => _answer(AgentDecision.allowForAWhile),
    ),
    DesktopButton(
      label: 'Allow Once',
      kind: DesktopButtonKind.primary,
      onPressed: () => _answer(AgentDecision.allowOnce),
    ),
  ];
}

/// The reason the agent gave, the items with what is asked of each, and
/// where the values go.
class _SecretDetails extends StatelessWidget {
  const _SecretDetails({required this.prompt});

  final SecretPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final secondary = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    final mono = AppText.mono(
      context,
      fontSize: DesktopMetrics.secondarySize,
      color: colors.text,
    );
    final delivery = prompt.delivery;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        DesktopGroupBox(
          title: 'Reason it gave',
          child: Text('“${prompt.reason}”'),
        ),
        DesktopGroupBox(
          title: prompt.items.length == 1
              ? 'Item'
              : '${prompt.items.length} items',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              for (final item in prompt.items)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      item.path,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(item.names.join(' · '), style: secondary),
                  ],
                ),
            ],
          ),
        ),
        switch (delivery.mode) {
          DeliveryMode.reveal => _Note(
            symbol: DesktopSymbol.warning,
            color: colors.warning,
            text:
                'The values go to ${prompt.client} and to the AI model '
                'behind it, and stay in that conversation.',
          ),
          DeliveryMode.file => DesktopGroupBox(
            title: 'Writes to (only you can read it)',
            child: Text(delivery.target!, style: mono),
          ),
          DeliveryMode.command => DesktopGroupBox(
            title: 'Runs, with the values as environment variables',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Text(delivery.target!, style: mono),
                Text(
                  'Its output comes back to ${prompt.client} with the '
                  'values blanked out.',
                  style: secondary,
                ),
              ],
            ),
          ),
        },
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.symbol, required this.color, required this.text});

  final DesktopSymbol symbol;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: DesktopIcon(symbol, size: 14, color: color),
      ),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: DesktopMetrics.secondarySize,
            color: context.desktopColors.text,
          ),
        ),
      ),
    ],
  );
}
