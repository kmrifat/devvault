import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:vault_core/vault_core.dart';

/// An app's initial on its colour; a folder for "No app".
class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.app, this.size = 20});

  final AppRecord? app;
  final double size;

  static const _palette = [
    Color(0xFFF07A3A),
    Color(0xFF0485F7),
    Color(0xFF8B5CF6),
    Color(0xFF0F9F94),
    Color(0xFF17A34A),
    Color(0xFFE5486A),
  ];

  /// The app's colour, picked from its id so it's the same on every
  /// device.
  static Color colorFor(AppRecord app) {
    final hash = app.id.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0xFFFFFF);
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final app = this.app;
    if (app == null) {
      return Icon(
        LucideIcons.folderOpen,
        size: size * 0.9,
        color: context.bcTheme.muted,
      );
    }
    final name = app.name.trim();
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colorFor(app),
        shape: BCShapes.continuous(size * 0.3),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(
              fontSize: size * 0.55,
              height: 1,
              fontWeight: BCTypography.bold,
              color: const Color(0xFFFFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}
