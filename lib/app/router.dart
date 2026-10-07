import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/create_vault/create_vault_screen.dart';
import '../features/create_vault/recovery_kit_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/unlock/recover_screen.dart';
import '../features/unlock/unlock_screen.dart';
import '../features/vault/item_detail_pane.dart';
import '../features/vault/vault_list_pane.dart';
import 'desktop_shell.dart';
import 'layout.dart';
import 'mobile_shell.dart';
import 'placeholder_screen.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Every route builds an explicit [MaterialPage]: a platform-native push
/// transition from the theme (iOS slide with edge swipe-back, Android's
/// predictive back) and the system back gesture everywhere.
///
/// Don't use `GoRoute.builder`: go_router 18 detects the app type by looking
/// for `material_ui`'s `MaterialApp`, which isn't the Flutter `MaterialApp`
/// this app (and bc_ui) uses, so it silently falls back to `NoTransitionPage`.
Page<void> materialPage(
  GoRouterState state,
  Widget child, {
  bool fullscreenDialog = false,
}) => MaterialPage<void>(
  key: state.pageKey,
  name: state.name ?? state.path,
  arguments: state.extra,
  restorationId: state.pageKey.value,
  fullscreenDialog: fullscreenDialog,
  child: child,
);

/// Builds the app router for [layout]. [initialLocation] lets tests and
/// `--dart-define=START=/vault` open any screen directly.
GoRouter buildRouter({
  required AppLayout layout,
  String initialLocation = Routes.unlock,
  Listenable? refreshListenable,
  String? Function(GoRouterState state)? redirect,
}) {
  final desktop = layout == AppLayout.desktop;

  /// A full-screen route above the shell.
  GoRoute page(
    String path,
    Widget Function(GoRouterState s) build, {
    bool fullscreenDialog = false,
  }) => GoRoute(
    path: path,
    parentNavigatorKey: rootNavigatorKey,
    pageBuilder: (_, s) =>
        materialPage(s, build(s), fullscreenDialog: fullscreenDialog),
  );

  /// A route inside a shell branch.
  GoRoute tab(
    String path,
    Widget Function(GoRouterState s) build, {
    List<RouteBase> routes = const [],
  }) => GoRoute(
    path: path,
    pageBuilder: (_, s) => materialPage(s, build(s)),
    routes: routes,
  );

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    errorPageBuilder: (_, s) => materialPage(s, const _NotFoundScreen()),
    routes: [
      // Lock screens and first run
      page(Routes.unlock, (_) => const UnlockScreen()),
      page(Routes.create, (_) => const CreateVaultScreen()),
      page(Routes.createRecoveryKit, (_) => const RecoveryKitScreen()),
      page(Routes.recover, (_) => const RecoverScreen()),
      page(
        Routes.pair,
        (_) => const PlaceholderScreen(
          title: 'Pair a device',
          frame: 'P4-06',
          icon: LucideIcons.qrCode,
        ),
        fullscreenDialog: true,
      ),

      // Item screen: pushed on mobile, a selection in the detail pane on
      // desktop.
      page(
        '/vault/item/:id',
        (s) => PlaceholderScreen(
          title: 'Item ${s.pathParameters['id']}',
          frame: 'B3',
          icon: LucideIcons.fileKey2,
        ),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => desktop
            ? DesktopShell(navigationShell: shell, uri: state.uri)
            : MobileShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              tab(
                Routes.vaultRoot,
                (s) => desktop
                    ? VaultPanes(
                        list: VaultListPane(uri: s.uri),
                        detail: ItemDetailPane(
                          itemId: s.uri.queryParameters['item'],
                        ),
                      )
                    : const PlaceholderScreen(
                        title: 'Vault',
                        frame: 'B2',
                        icon: LucideIcons.layers,
                      ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              tab(
                Routes.expiry,
                (_) => const PlaceholderScreen(
                  title: 'Expiry',
                  frame: 'D06',
                  icon: LucideIcons.clockAlert,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              tab(
                Routes.settings,
                (_) => const SettingsScreen(),
                routes: [
                  tab(
                    'sync',
                    (_) => const PlaceholderScreen(
                      title: 'Sync storage',
                      frame: 'D07',
                      icon: LucideIcons.cloud,
                    ),
                  ),
                  tab('security', (_) => const SettingsScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      // The vault session decides first: create, unlock or carry on.
      final sessionTarget = redirect?.call(state);
      if (sessionTarget != null) return sessionTarget;

      // On desktop an item is a selection in the vault's detail pane.
      final segments = state.uri.pathSegments;
      if (desktop &&
          segments.length == 3 &&
          segments[0] == 'vault' &&
          segments[1] == 'item') {
        return Routes.vault(item: segments[2]);
      }
      return null;
    },
  );
}

/// Shown for an unknown path (a stale deep link, a typo in a route).
class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bcTheme.background,
      body: Center(
        child: BCEmptyState(
          icon: const Icon(LucideIcons.compass),
          title: 'Page not found',
          actions: [
            BCButton(
              onPressed: () => context.go(Routes.vault()),
              child: const Text('Go to vault'),
            ),
          ],
        ),
      ),
    );
  }
}
