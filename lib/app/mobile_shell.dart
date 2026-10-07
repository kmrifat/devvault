import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The phone layout (design frame B2): the selected branch with a floating
/// bottom nav over it.
class MobileShell extends StatelessWidget {
  const MobileShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bcTheme.background,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: BCBottomNav(
        variant: BCBottomNavVariant.floating,
        currentIndex: navigationShell.currentIndex,
        onTap: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        items: const [
          BCBottomNavItem(icon: Icon(LucideIcons.layers), label: 'Vault'),
          BCBottomNavItem(icon: Icon(LucideIcons.clock), label: 'Expiry'),
          BCBottomNavItem(icon: Icon(LucideIcons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
