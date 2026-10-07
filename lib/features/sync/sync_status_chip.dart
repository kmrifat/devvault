import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/providers.dart';
import '../../data/sync_controller.dart';
import '../../data/sync_setup.dart';
import '../../shared/ui.dart';

/// The toolbar's sync line (design frame D03: "Synced · R2 · 2 min ago").
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
    final label = ref.watch(storageLabelProvider);
    final now = ref.watch(clockProvider)();
    String since(DateTime? t) =>
        t == null ? '' : ' · ${SyncStatusChip.ago(t, now)}';
    void sync() => ref.read(syncControllerProvider.notifier).syncNow();
    void settings() => context.go(Routes.settingsSync);

    final (color, icon, text, onPressed, tooltip) = switch (status) {
      SyncOff() => (
        BCChipColor.defaultColor,
        LucideIcons.cloudOff,
        'Not syncing',
        settings,
        'Set up sync storage',
      ),
      SyncRunning() => (BCChipColor.accent, null, 'Syncing…', null, null),
      SyncIdle(:final conflicts) when conflicts > 0 => (
        BCChipColor.warning,
        LucideIcons.gitMerge,
        conflicts == 1 ? '1 conflict' : '$conflicts conflicts',
        sync,
        'Items changed on two devices need your choice',
      ),
      SyncIdle(:final lastSync) => (
        BCChipColor.success,
        LucideIcons.cloudCheck,
        lastSync == null
            ? 'Sync on${label == null ? '' : ' · $label'}'
            : 'Synced${label == null ? '' : ' · $label'}${since(lastSync)}',
        sync,
        'Sync now (⌘R)',
      ),
      SyncOffline(:final lastSync) => (
        BCChipColor.warning,
        LucideIcons.cloudOff,
        'Offline${lastSync == null ? '' : ' · synced${since(lastSync)}'}',
        sync,
        'Changes stay on this device until the storage is reachable',
      ),
      SyncFailed(:final message) => (
        BCChipColor.danger,
        LucideIcons.cloudAlert,
        'Sync paused',
        settings,
        message,
      ),
    };
    _ticking(switch (status) {
      SyncIdle(lastSync: _?) || SyncOffline(lastSync: _?) => true,
      _ => false,
    });

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
