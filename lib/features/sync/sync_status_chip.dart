import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/shortcuts.dart';
import '../../data/providers.dart';
import '../../data/sync_controller.dart';
import '../../data/sync_setup.dart';
import '../../shared/ui.dart';
import 'adopt_key_dialog.dart';

/// What the sync line says, whichever widget draws it.
enum SyncLineState {
  off,
  running,
  conflicts,
  synced,
  offline,
  keyChanged,
  failed,
}

/// The sync status in words ("Synced · R2 · 2 min ago"), what clicking it
/// does (sync now; open the settings when sync is off or failing) and its
/// tooltip.
({SyncLineState state, String text, VoidCallback? onPressed, String? tooltip})
describeSync(BuildContext context, WidgetRef ref) {
  final status = ref.watch(syncControllerProvider);
  final label = ref.watch(storageLabelProvider);
  final now = ref.watch(clockProvider)();
  String since(DateTime? t) =>
      t == null ? '' : ' · ${SyncStatusChip.ago(t, now)}';
  void sync() => ref.read(syncControllerProvider.notifier).syncNow();
  void settings() => context.go(Routes.settingsSync);

  final (state, text, onPressed, tooltip) = switch (status) {
    SyncOff() => (
      SyncLineState.off,
      'Not syncing',
      settings,
      'Set up sync storage',
    ),
    SyncRunning() => (SyncLineState.running, 'Syncing…', null, null),
    SyncIdle(:final conflicts) when conflicts > 0 => (
      SyncLineState.conflicts,
      conflicts == 1 ? '1 conflict' : '$conflicts conflicts',
      sync,
      'Items changed on two devices need your choice',
    ),
    SyncIdle(:final lastSync) => (
      SyncLineState.synced,
      lastSync == null
          ? 'Sync on${label == null ? '' : ' · $label'}'
          : 'Synced${label == null ? '' : ' · $label'}${since(lastSync)}',
      sync,
      'Sync now (${shortcutLabel('R')})',
    ),
    SyncOffline(:final lastSync) => (
      SyncLineState.offline,
      'Offline${lastSync == null ? '' : ' · synced${since(lastSync)}'}',
      sync,
      'Changes stay on this device until the storage is reachable',
    ),
    SyncKeyChanged() => (
      SyncLineState.keyChanged,
      'Vault key changed',
      () => showAdoptKeyDialog(context),
      'Changed on another device: enter your master password to go on',
    ),
    SyncFailed(:final message) => (
      SyncLineState.failed,
      'Sync paused',
      settings,
      message,
    ),
  };
  return (state: state, text: text, onPressed: onPressed, tooltip: tooltip);
}

/// Whether the sync line shows a time that has to be kept current.
bool syncShowsTime(SyncStatus status) => switch (status) {
  SyncIdle(lastSync: _?) || SyncOffline(lastSync: _?) => true,
  _ => false,
};

/// The phone's sync chip (design frame B2: "Synced · R2 · 2 min ago").
/// Tap to sync now; when sync is off or failing, it opens the settings.
class SyncStatusChip extends ConsumerStatefulWidget {
  const SyncStatusChip({super.key});

  /// "just now", "4 min ago", "3 h ago", "2 days ago".
  static String ago(DateTime then, DateTime now) {
    final d = now.difference(then);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
  }

  @override
  ConsumerState<SyncStatusChip> createState() => _SyncStatusChipState();
}

class _SyncStatusChipState extends ConsumerState<SyncStatusChip> {
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
    final status = ref.watch(syncControllerProvider);
    final line = describeSync(context, ref);
    final (color, icon) = switch (line.state) {
      SyncLineState.off => (BCChipColor.defaultColor, LucideIcons.cloudOff),
      SyncLineState.running => (BCChipColor.accent, null),
      SyncLineState.conflicts => (BCChipColor.warning, LucideIcons.gitMerge),
      SyncLineState.synced => (BCChipColor.success, LucideIcons.cloudCheck),
      SyncLineState.offline => (BCChipColor.warning, LucideIcons.cloudOff),
      SyncLineState.keyChanged => (BCChipColor.warning, LucideIcons.keyRound),
      SyncLineState.failed => (BCChipColor.danger, LucideIcons.cloudAlert),
    };
    final (text, onPressed, tooltip) = (
      line.text,
      line.onPressed,
      line.tooltip,
    );
    _ticking(syncShowsTime(status));

    final chip = BCChip(
      size: BCChipSize.md,
      variant: color == BCChipColor.defaultColor
          ? BCChipVariant.secondary
          : BCChipVariant.soft,
      color: color,
      onPressed: onPressed,
      startContent: icon == null
          ? const BCSpinner(size: BCSpinnerSize.sm)
          : Icon(icon, size: 15),
      child: Text(text),
    );
    return Semantics(
      label: 'Sync: $text',
      child: tooltip == null ? chip : Tooltip(message: tooltip, child: chip),
    );
  }
}
