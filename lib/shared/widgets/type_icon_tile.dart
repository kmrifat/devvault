import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/theme.dart';

/// The rounded icon square that marks an item's type in lists and headers.
class TypeIconTile extends StatelessWidget {
  const TypeIconTile({super.key, required this.type, this.size = 40});

  final ItemType type;

  /// Edge length. The icon is half of it and the corners scale with it.
  final double size;

  static IconData iconFor(ItemType type) => switch (type) {
    ItemType.appleAuthKey => LucideIcons.keyRound,
    ItemType.appleCertificate => LucideIcons.badgeCheck,
    ItemType.provisioningProfile => LucideIcons.scrollText,
    ItemType.androidKeystore => LucideIcons.keySquare,
    ItemType.firebaseConfig => LucideIcons.flame,
    ItemType.gcpServiceAccount => LucideIcons.bot,
    ItemType.oauthClient => LucideIcons.shieldUser,
    ItemType.sshKey => LucideIcons.squareTerminal,
    ItemType.genericFile => LucideIcons.fileText,
    ItemType.genericSecret => LucideIcons.asterisk,
    ItemType.secureNote => LucideIcons.notebookText,
  };

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final app = context.appColors;
    final (background, foreground) = switch (type) {
      ItemType.appleAuthKey ||
      ItemType.gcpServiceAccount => (bc.accentSoft, bc.accentSoftForeground),
      ItemType.appleCertificate => (bc.defaultColor, bc.foreground),
      ItemType.provisioningProfile => (app.violetSoft, app.violet),
      ItemType.androidKeystore => (bc.successSoft, bc.successSoftForeground),
      ItemType.firebaseConfig => (bc.warningSoft, bc.warningSoftForeground),
      ItemType.oauthClient => (app.tealSoft, app.teal),
      ItemType.sshKey => (bc.defaultColor, bc.foreground),
      ItemType.genericFile ||
      ItemType.genericSecret ||
      ItemType.secureNote => (bc.defaultColor, bc.muted),
    };

    return Semantics(
      label: type.label,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: background,
          shape: BCShapes.continuous(size * 0.3),
        ),
        child: SizedBox.square(
          dimension: size,
          child: Icon(iconFor(type), size: size / 2, color: foreground),
        ),
      ),
    );
  }
}
