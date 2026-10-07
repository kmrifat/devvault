import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/expiry_alerts.dart';
import '../data/providers.dart';
import '../data/vault_session.dart';
import 'auto_lock.dart';
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
  });

  /// Where the app opens. Tests and `--dart-define=START=` set it.
  final String initialLocation;

  /// Overrides the platform's layout (tests render both).
  final AppLayout? layout;

  @override
  ConsumerState<DevVaultApp> createState() => _DevVaultAppState();
}

class _DevVaultAppState extends ConsumerState<DevVaultApp> {
  /// Re-runs the router's redirect whenever the session or the pending
  /// recovery key changes (unlock, lock, create).
  final _sessionChanges = ValueNotifier<int>(0);

  late final GoRouter _router = buildRouter(
    layout: widget.layout ?? AppLayout.current,
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
    ref.listenManual(vaultSessionProvider, (_, _) => _sessionChanges.value++);
    ref.listenManual(
      pendingRecoveryKeyProvider,
      (_, _) => _sessionChanges.value++,
    );
    ref.listenManual(
      passwordResetPendingProvider,
      (_, _) => _sessionChanges.value++,
    );
    // Keeps expiry reminders in step with the vault from here on.
    ref.read(expiryAlertsProvider);
  }

  @override
  void dispose() {
    _router.dispose();
    _sessionChanges.dispose();
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
      builder: (context, child) =>
          AutoLock(child: BCToastProvider(child: child!)),
    );
  }
}
