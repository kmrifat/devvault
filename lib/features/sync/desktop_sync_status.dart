import 'dart:async';

import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync_controller.dart';
import '../../shared/desktop_ui.dart';
import 'sync_status_chip.dart' show SyncLineState, describeSync, syncShowsTime;

/// The toolbar's sync status (design frame N03: "Synced · 2 min ago"): an
/// icon in the status colour and the line in secondary text. Click to sync
/// now; when sync is off or failing, it opens the settings.
class DesktopSyncStatus extends ConsumerStatefulWidget {
  const DesktopSyncStatus({super.key});

  @override
  ConsumerState<DesktopSyncStatus> createState() => _DesktopSyncStatusState();
}

class _DesktopSyncStatusState extends ConsumerState<DesktopSyncStatus> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Keeps "n min ago" current while a time is shown.
  void _ticking(bool on) {
    if (on && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    _ticking(syncShowsTime(ref.watch(syncControllerProvider)));
    final line = describeSync(context, ref);
    final (symbol, color) = switch (line.state) {
      SyncLineState.off => (DesktopSymbol.syncOff, colors.secondaryText),
      SyncLineState.running => (DesktopSymbol.syncing, colors.accentIcon),
      SyncLineState.conflicts => (DesktopSymbol.conflicts, colors.conflict),
      SyncLineState.synced => (DesktopSymbol.synced, colors.success),
      SyncLineState.offline => (DesktopSymbol.syncOff, colors.warning),
      SyncLineState.keyChanged => (DesktopSymbol.keyChanged, colors.warning),
      SyncLineState.failed => (DesktopSymbol.syncFailed, colors.danger),
    };
    final content = Semantics(
      button: line.onPressed != null,
      label: 'Sync: ${line.text}',
      onTap: line.onPressed,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: line.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              DesktopIcon(symbol, size: 14, color: color),
              Text(
                line.text,
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize + 1,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final tooltip = line.tooltip;
    return tooltip == null
        ? content
        : Tooltip(message: tooltip, child: content);
  }
}
