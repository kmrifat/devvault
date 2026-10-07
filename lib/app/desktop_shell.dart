import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The desktop window (design frame D03): a permanent sidebar next to the
/// content of the selected branch.
///
/// The sidebar's destinations map one-to-one onto the shell branches
/// (Vault, Expiry, Settings). The App → Platform → Environment tree and tags
/// arrive with the real sidebar in P1-06.
class DesktopShell extends StatelessWidget {
  const DesktopShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const double sidebarWidth = 264;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Scaffold(
      backgroundColor: bc.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BCNavDrawer(
            width: sidebarWidth,
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (i) => navigationShell.goBranch(
              i,
              initialLocation: i == navigationShell.currentIndex,
            ),
            header: const _VaultHeader(),
            items: const [
              BCNavDrawerDestination(
                icon: Icon(LucideIcons.layers),
                label: 'All items',
              ),
              BCNavDrawerDestination(
                icon: Icon(LucideIcons.clockAlert),
                label: 'Expiry',
              ),
              BCNavDrawerDivider(),
              BCNavDrawerDestination(
                icon: Icon(LucideIcons.settings),
                label: 'Settings',
              ),
            ],
          ),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

class _VaultHeader extends StatelessWidget {
  const _VaultHeader();

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Row(
      spacing: BCSpacing.sm,
      children: [
        Icon(LucideIcons.vault, color: bc.accent),
        const BCText('DevVault', type: BCTextType.h6),
      ],
    );
  }
}

/// The vault branch on desktop: item list and detail side by side.
///
/// Placeholder panes until P1-07 (list) and P1-08 (detail).
class VaultPanes extends StatelessWidget {
  const VaultPanes({super.key, required this.list, required this.detail});

  final Widget list;
  final Widget detail;

  static const double listWidth = 420;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: listWidth, child: list),
        VerticalDivider(width: 1, thickness: 1, color: bc.border),
        Expanded(child: detail),
      ],
    );
  }
}
