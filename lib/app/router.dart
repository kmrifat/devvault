import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/expiry/expiry_screen.dart';
import '../features/pairing/pair_screen.dart';
import '../features/create_vault/create_vault_screen.dart';
import '../features/create_vault/join_vault_screen.dart';
import '../features/create_vault/recovery_kit_screen.dart';
import '../features/settings/settings_layout.dart' show SettingsPane;
import '../features/settings/settings_screen.dart';
import '../features/settings/sync_settings_screen.dart';
import '../features/unlock/recover_screen.dart';
import '../features/unlock/unlock_screen.dart';
import '../features/vault/item_detail_pane.dart';
import '../features/vault/item_screen.dart';
import '../features/vault/mobile_vault_screen.dart';
import '../features/vault/vault_list_pane.dart';
import 'desktop_shell.dart';
import 'layout.dart';
import 'mobile_shell.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Every route builds an explicit [MaterialPage]: a platform-native push
/// transition from the theme (iOS slide with edge swipe-back, Android's
/// predictive back) and the system back gesture everywhere.
///
/// Don't use `GoRoute.builder`: go_router 18 detects the app type by looking
/// for `material_ui`'s `MaterialApp`, which isn't the Flutter `MaterialApp`
/// this app (and bc_ui) uses, so it silently falls back to `NoTransitionPage`.
///
/// [key] replaces the route's own page key: routes that share one show as
/// a single page whose content changes in place, with no transition.
Page<void> materialPage(
  GoRouterState state,
  Widget child, {
  bool fullscreenDialog = false,
  LocalKey? key,
}) => MaterialPage<void>(
  key: key ?? state.pageKey,
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
      page(Routes.joinVault, (_) => const JoinVaultScreen()),
      page(Routes.recover, (_) => const RecoverScreen()),
      page(Routes.pair, (_) => const PairScreen(), fullscreenDialog: true),

      // Item screen: pushed on mobile, a selection in the detail pane on
      // desktop.
      page(
        '/vault/item/:id',
        (s) => ItemScreen(itemId: s.pathParameters['id']!),
      ),

      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, shell) => materialPage(
          state,
          desktop
              ? DesktopShell(navigationShell: shell, uri: state.uri)
              : MobileShell(navigationShell: shell),
        ),
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
                    : MobileVaultScreen(uri: s.uri),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              tab(
                Routes.expiry,
                (s) => ExpiryScreen(uri: s.uri, desktop: desktop),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: desktop
                // Desktop: one Settings page with a tab per pane. The
                // panes share a page, so a tab swaps its content in place
                // instead of pushing a screen.
                ? [
                    for (final pane in SettingsPane.values)
                      GoRoute(
                        path: pane.route,
                        pageBuilder: (_, s) => materialPage(
                          s,
                          SettingsScreen(pane: pane),
                          key: const ValueKey('settings'),
                        ),
                      ),
                  ]
                : [
                    tab(
                      Routes.settings,
                      (_) => const SettingsScreen(),
                      routes: [
                        tab('sync', (_) => const SyncSettingsScreen()),
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
