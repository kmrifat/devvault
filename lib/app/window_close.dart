import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../data/app_settings.dart';
import '../data/providers.dart';
import '../data/vault_session.dart';

/// Whether closing the window should keep DevVault running (P5): only
/// where agents are supported, while they're on, and while the user wants
/// it.
bool keepsRunningWhenClosed(AppSettings settings, {required bool supported}) =>
    supported && settings.agentsEnabled && settings.keepRunningWhenClosed;

/// Closing the window, while [keepsRunningWhenClosed]: locks the vault and
/// hides the window instead of quitting, so AI agents can still reach
/// DevVault. Clicking the Dock icon shows it again (AppDelegate.swift);
/// an agent's request brings it forward; ⌘Q still quits.
///
/// Only around the app's own native window: `main()` sets that, tests
/// don't.
class KeepRunningOnClose extends ConsumerStatefulWidget {
  const KeepRunningOnClose({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<KeepRunningOnClose> createState() => _KeepRunningOnCloseState();
}

class _KeepRunningOnCloseState extends ConsumerState<KeepRunningOnClose>
    with WindowListener {
  bool _keepRunning = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _apply();
    ref.listenManual(settingsProvider, (_, _) => _apply());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _apply() {
    final keep = keepsRunningWhenClosed(
      ref.read(settingsProvider),
      supported: ref.read(agentSocketPathProvider) != null,
    );
    if (keep == _keepRunning) return;
    _keepRunning = keep;
    windowManager.setPreventClose(keep);
  }

  @override
  Future<void> onWindowClose() async {
    if (!_keepRunning) return;
    // Hidden means locked: nothing decrypted sits behind a closed window.
    ref.read(vaultSessionProvider.notifier).lock();
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
