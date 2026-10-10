import 'dart:ui' show AppExitType;

import 'package:flutter/material.dart' show showAboutDialog;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import '../data/sync_controller.dart';
import '../data/vault_session.dart';
import '../shared/desktop_ui.dart';
import 'desktop_commands.dart';
import 'routes.dart';

/// The app's menus on desktop (design doc › Menu bar): DevVault, File,
/// Edit, View, Vault, Window and Help on macOS; File, Edit, View, Vault and
/// Help in the window on Windows and Linux. Everything that needs the vault
/// is disabled while it's locked.
class AppMenus extends ConsumerWidget {
  const AppMenus({
    super.key,
    required this.router,
    required this.commands,
    required this.child,
  });

  final GoRouter router;
  final DesktopCommands commands;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(vaultSessionProvider) is Unlocked;
    final syncing = ref.watch(syncControllerProvider) is! SyncOff;
    final macos = DesktopTheme.of(context).kit == DesktopKit.macos;
    return ListenableBuilder(
      listenable: commands,
      builder: (context, _) => DesktopMenuBar(
        menus: menus(
          macos: macos,
          unlocked: unlocked,
          syncing: syncing,
          go: router.go,
          lock: () => ref.read(vaultSessionProvider.notifier).lock(),
          syncNow: () => ref.read(syncControllerProvider.notifier).syncNow(),
          open: (link) => ref.read(linkOpenerProvider).open(link),
          about: () {
            final context = router.routerDelegate.navigatorKey.currentContext;
            if (context != null) {
              showAboutDialog(context: context, applicationName: 'DevVault');
            }
          },
          commands: commands,
        ),
        child: child,
      ),
    );
  }

  /// The pages Help opens: the project's README, the AI agents guide
  /// (docs/agent/USING.md) and a new GitHub issue.
  static final helpLink = Uri.parse(
    'https://github.com/kmrifat/devvault#readme',
  );
  static final agentsGuideLink = Uri.parse(
    'https://github.com/kmrifat/devvault/blob/main/docs/agent/USING.md',
  );
  static final issueLink = Uri.parse(
    'https://github.com/kmrifat/devvault/issues/new',
  );

  /// The menus for one state of the app. [macos] adds the items macOS
  /// provides (About, Hide, Quit, the Window menu) and the Edit commands,
  /// which its menu bar takes over from text fields. Help's items work
  /// while the vault is locked: they only open web pages.
  @visibleForTesting
  static List<DesktopMenu> menus({
    required bool macos,
    required bool unlocked,
    required bool syncing,
    required void Function(String location) go,
    required VoidCallback lock,
    required VoidCallback syncNow,
    required void Function(Uri link) open,
    required VoidCallback about,
    required DesktopCommands commands,
  }) {
    VoidCallback? whenUnlocked(VoidCallback? action) =>
        unlocked ? action : null;
    SingleActivator key(LogicalKeyboardKey trigger, {bool shift = false}) =>
        SingleActivator(trigger, meta: macos, control: !macos, shift: shift);
    final settings = DesktopMenuItem(
      macos ? 'Settings…' : 'Settings',
      shortcut: macos ? key(LogicalKeyboardKey.comma) : null,
      onSelected: whenUnlocked(() => go(Routes.settings)),
    );
    final quit = DesktopMenuItem(
      'Quit',
      onSelected: () =>
          ServicesBinding.instance.exitApplication(AppExitType.required),
    );
    return [
      if (macos)
        DesktopMenu('DevVault', [
          const DesktopMenuProvided(PlatformProvidedMenuItemType.about),
          const DesktopMenuDivider(),
          settings,
          const DesktopMenuDivider(),
          const DesktopMenuProvided(PlatformProvidedMenuItemType.hide),
          const DesktopMenuProvided(
            PlatformProvidedMenuItemType.hideOtherApplications,
          ),
          const DesktopMenuProvided(
            PlatformProvidedMenuItemType.showAllApplications,
          ),
          const DesktopMenuDivider(),
          const DesktopMenuProvided(PlatformProvidedMenuItemType.quit),
        ]),
      DesktopMenu('File', [
        DesktopMenuItem(
          'New Item',
          shortcut: key(LogicalKeyboardKey.keyN),
          onSelected: whenUnlocked(commands.newItem),
        ),
        DesktopMenuItem(
          'New Secure Note',
          shortcut: key(LogicalKeyboardKey.keyN, shift: true),
          onSelected: whenUnlocked(commands.newSecureNote),
        ),
        DesktopMenuItem(
          'Import…',
          shortcut: key(LogicalKeyboardKey.keyI),
          onSelected: whenUnlocked(commands.importFile),
        ),
        if (!macos) ...[const DesktopMenuDivider(), settings],
        if (!macos) ...[const DesktopMenuDivider(), quit],
      ]),
      DesktopMenu('Edit', [
        if (macos) ...[
          DesktopMenuItem(
            'Undo',
            shortcut: key(LogicalKeyboardKey.keyZ),
            onSelected: () => _onFocused(
              const UndoTextIntent(SelectionChangedCause.keyboard),
            ),
          ),
          DesktopMenuItem(
            'Redo',
            shortcut: key(LogicalKeyboardKey.keyZ, shift: true),
            onSelected: () => _onFocused(
              const RedoTextIntent(SelectionChangedCause.keyboard),
            ),
          ),
          const DesktopMenuDivider(),
          DesktopMenuItem(
            'Cut',
            shortcut: key(LogicalKeyboardKey.keyX),
            onSelected: () => _onFocused(
              const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
            ),
          ),
          DesktopMenuItem(
            'Copy',
            shortcut: key(LogicalKeyboardKey.keyC),
            onSelected: () => _onFocused(CopySelectionTextIntent.copy),
          ),
          DesktopMenuItem(
            'Paste',
            shortcut: key(LogicalKeyboardKey.keyV),
            onSelected: () => _onFocused(
              const PasteTextIntent(SelectionChangedCause.keyboard),
            ),
          ),
          DesktopMenuItem(
            'Select All',
            shortcut: key(LogicalKeyboardKey.keyA),
            onSelected: () => _onFocused(
              const SelectAllTextIntent(SelectionChangedCause.keyboard),
            ),
          ),
          const DesktopMenuDivider(),
        ],
        DesktopMenuItem(
          'Find',
          shortcut: key(LogicalKeyboardKey.keyF),
          onSelected: whenUnlocked(commands.find),
        ),
      ]),
      DesktopMenu('View', [
        DesktopMenuItem(
          'Quick Open',
          shortcut: key(LogicalKeyboardKey.keyK),
          onSelected: whenUnlocked(commands.quickOpen),
        ),
        if (macos) ...[
          const DesktopMenuDivider(),
          const DesktopMenuProvided(
            PlatformProvidedMenuItemType.toggleFullScreen,
          ),
        ],
      ]),
      DesktopMenu('Vault', [
        DesktopMenuItem(
          'Sync Now',
          shortcut: key(LogicalKeyboardKey.keyR),
          onSelected: whenUnlocked(syncing ? syncNow : null),
        ),
        DesktopMenuItem(
          'Lock',
          shortcut: key(LogicalKeyboardKey.keyL),
          onSelected: whenUnlocked(lock),
        ),
        const DesktopMenuDivider(),
        DesktopMenuItem(
          'Expiry',
          onSelected: whenUnlocked(() => go(Routes.expiry)),
        ),
      ]),
      if (macos)
        const DesktopMenu('Window', [
          DesktopMenuProvided(PlatformProvidedMenuItemType.minimizeWindow),
          DesktopMenuProvided(PlatformProvidedMenuItemType.zoomWindow),
          DesktopMenuDivider(),
          DesktopMenuProvided(
            PlatformProvidedMenuItemType.arrangeWindowsInFront,
          ),
        ]),
      DesktopMenu('Help', [
        DesktopMenuItem('DevVault Help', onSelected: () => open(helpLink)),
        DesktopMenuItem(
          'Using DevVault with AI Agents',
          onSelected: () => open(agentsGuideLink),
        ),
        const DesktopMenuDivider(),
        DesktopMenuItem('Report an Issue…', onSelected: () => open(issueLink)),
        // macOS has About in the app menu.
        if (!macos) ...[
          const DesktopMenuDivider(),
          DesktopMenuItem('About DevVault', onSelected: about),
        ],
      ]),
    ];
  }

  /// Runs a text-editing [intent] on whatever has keyboard focus: macOS's
  /// menu bar takes these keys before the text field sees them.
  static void _onFocused(Intent intent) {
    final context = primaryFocus?.context;
    if (context != null) Actions.maybeInvoke(context, intent);
  }
}
