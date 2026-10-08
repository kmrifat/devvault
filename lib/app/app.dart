import 'dart:async';

import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/agent_bridge.dart';
import '../data/expiry_alerts.dart';
import '../data/providers.dart';
import '../data/sync_controller.dart';
import '../data/vault_session.dart';
import '../features/agents/agent_prompt_sheet.dart';
import '../features/settings/new_recovery_kit_dialog.dart';
import '../shared/desktop/desktop_theme.dart';
import 'app_menus.dart';
import 'auto_lock.dart';
import 'desktop_commands.dart';
import 'incoming_imports.dart';
import 'layout.dart';
import 'router.dart';
import 'routes.dart';
import 'session_redirect.dart';
import 'theme.dart';

class DevVaultApp extends ConsumerStatefulWidget {
  const DevVaultApp({
    super.key,
    this.initialLocation = Routes.unlock,
    this.layout,
    this.nativeWindow = false,
  });

  /// Where the app opens. Tests and `--dart-define=START=` set it.
  final String initialLocation;

  /// Overrides the platform's layout (tests render both).
  final AppLayout? layout;

  /// Whether the desktop window is the app's own native window (see
  /// [DesktopTheme.nativeWindow]); `main()` sets it, tests don't.
  final bool nativeWindow;

  @override
  ConsumerState<DevVaultApp> createState() => _DevVaultAppState();
}

class _DevVaultAppState extends ConsumerState<DevVaultApp> {
  /// Re-runs the router's redirect whenever the session or the pending
  /// recovery key changes (unlock, lock, create).
  final _sessionChanges = ValueNotifier<int>(0);

  late final AppLayout _layout = widget.layout ?? AppLayout.current;

  /// What the desktop menu bar asks the open vault window to do.
  final _commands = DesktopCommands();

  late final GoRouter _router = buildRouter(
    layout: _layout,
    initialLocation: widget.initialLocation,
    refreshListenable: _sessionChanges,
    redirect: (state) => sessionRedirect(
      ref.read(vaultSessionProvider),
      state.uri,
      recoveryKitPending: ref.read(pendingRecoveryKeyProvider) != null,
      passwordResetPending: ref.read(passwordResetPendingProvider),
    ),
  );

  @override
  void initState() {
    super.initState();
    ref.listenManual(vaultSessionProvider, (previous, next) {
      _sessionChanges.value++;
      if (previous is! Unlocked && next is Unlocked) _offerFinishedRotation();
    });
    ref.listenManual(
      pendingRecoveryKeyProvider,
      (_, _) => _sessionChanges.value++,
    );
    ref.listenManual(
      passwordResetPendingProvider,
      (_, _) => _sessionChanges.value++,
    );
    // Keeps sync's triggers alive for the whole app, not just while the
    // status chip is on screen.
    ref.listenManual(syncControllerProvider, (_, _) {});
    // Keeps expiry reminders in step with the vault from here on.
    ref.read(expiryAlertsProvider);
    // Serves AI agents while Settings › AI Agents is on (P5), and puts
    // what they ask in front of the user, one sheet at a time.
    ref.listenManual(
      agentBridgeProvider.select((s) => s.prompts),
      (_, _) => _showAgentPrompt(),
    );
  }

  /// An interrupted key rotation is finished by a password unlock (SPEC
  /// §9); its new recovery key has never been shown. Show it once.
  void _offerFinishedRotation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = ref
          .read(vaultSessionProvider.notifier)
          .takePendingRecoveryKey();
      if (key == null) return;
      final context = _router.routerDelegate.navigatorKey.currentContext;
      if (context == null) {
        key.dispose();
        return;
      }
      showFinishedRotationDialog(context, key);
    });
  }

  bool _showingAgentPrompt = false;

  Future<void> _showAgentPrompt() async {
    if (_showingAgentPrompt) return;
    final prompt = ref
        .read(agentBridgeProvider)
        .prompts
        .where((p) => !p.isClosed)
        .firstOrNull;
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (prompt == null || context == null) return;
    _showingAgentPrompt = true;
    try {
      final decision = await showAgentPromptSheet(context, prompt);
      ref
          .read(agentBridgeProvider.notifier)
          .answer(prompt, decision ?? AgentDecision.deny);
    } finally {
      _showingAgentPrompt = false;
    }
    if (mounted) unawaited(_showAgentPrompt());
  }

  @override
  void dispose() {
    _router.dispose();
    _sessionChanges.dispose();
    _commands.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DevVault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(settingsProvider.select((s) => s.themeMode)),
      routerConfig: _router,
      builder: (context, child) {
        final app = AutoLock(
          child: BCToastProvider(child: IncomingImports(child: child!)),
        );
        // Desktop controls are drawn by the OS's own kit (ADR-0005). Around
        // the Navigator, so menus the kits open as routes are themed too.
        if (_layout != AppLayout.desktop) return app;
        return DesktopTheme(
          nativeWindow: widget.nativeWindow,
          child: DesktopCommandsScope(
            commands: _commands,
            child: AppMenus(router: _router, commands: _commands, child: app),
          ),
        );
      },
    );
  }
}
