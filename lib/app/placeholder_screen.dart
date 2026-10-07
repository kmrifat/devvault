import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';

/// Stand-in for a screen that a later milestone builds. It names the design
/// frame it will implement so the route map can be checked end to end
/// before any feature exists.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.frame,
    this.icon,
  });

  final String title;

  /// Design frame ID in `design/DevVault.fig`, e.g. `D00` or `B2`.
  final String frame;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bcTheme.background,
      body: Center(
        child: BCEmptyState(
          icon: icon == null ? null : Icon(icon),
          title: title,
          description: 'Design frame $frame',
        ),
      ),
    );
  }
}
