import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../data/providers.dart';

/// The phone layout (design frame B2): the selected branch with the tab bar
/// over it.
///
/// On iPhone the tab bar is UIKit's own (`native_liquid_glass`): Liquid
/// Glass on iOS 26, the standard bar before it, with SF Symbols. It hides
/// itself while a sheet or dialog covers the shell. Android, and tests
/// ([nativeBarsProvider]), keep bc_ui's floating bar.
class MobileShell extends ConsumerWidget {
  const MobileShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// The branches, in order: label, Lucide icon, SF Symbol (and its filled
  /// form for the selected tab).
  static const _tabs = [
    ('Vault', LucideIcons.layers, 'square.stack.3d.up'),
    ('Expiry', LucideIcons.clock, 'clock'),
    ('Settings', LucideIcons.settings, 'gearshape'),
  ];

  void _select(int i) => navigationShell.goBranch(
    i,
    initialLocation: i == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bc = context.bcTheme;
    return Scaffold(
      backgroundColor: bc.background,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: ref.watch(nativeBarsProvider)
          ? LiquidGlassTabBar(
              currentIndex: navigationShell.currentIndex,
              onTabSelected: _select,
              selectedItemColor: bc.accent,
              items: [
                for (final (label, _, symbol) in _tabs)
                  LiquidGlassTabItem(
                    label: label,
                    icon: NativeLiquidGlassIcon.sfSymbol(symbol),
                    selectedIcon: NativeLiquidGlassIcon.sfSymbol(
                      '$symbol.fill',
                    ),
                  ),
              ],
            )
          : BCBottomNav(
              variant: BCBottomNavVariant.floating,
              currentIndex: navigationShell.currentIndex,
              onTap: _select,
              items: [
                for (final (label, icon, _) in _tabs)
                  BCBottomNavItem(icon: Icon(icon), label: label),
              ],
            ),
    );
  }
}
