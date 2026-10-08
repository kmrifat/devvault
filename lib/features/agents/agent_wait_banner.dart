import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/agent_bridge.dart';
import '../../shared/desktop_ui.dart';

/// On the unlock screen while an AI agent waits for the vault: who, and
/// for what. Nothing while no one waits.
class AgentWaitBanner extends ConsumerWidget {
  const AgentWaitBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waits = ref.watch(agentBridgeProvider.select((s) => s.waits));
    if (waits.isEmpty) return const SizedBox.shrink();
    final colors = context.desktopColors;
    final first = waits.first;
    final more = waits.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.groupBox,
            border: Border.all(color: colors.groupBoxStroke, width: 0.5),
            borderRadius: const BorderRadius.all(
              Radius.circular(DesktopMetrics.menuRadius + 2),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                DesktopIcon(
                  DesktopSymbol.agent,
                  size: 14,
                  color: colors.accentIcon,
                ),
                Flexible(
                  child: Text(
                    '${first.client} is waiting ${first.what}'
                    '${more > 0 ? ', with $more more' : ''}. Unlock to '
                    'continue.',
                    style: TextStyle(
                      fontSize: DesktopMetrics.secondarySize,
                      color: colors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
