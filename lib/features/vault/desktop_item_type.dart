import 'package:vault_core/vault_core.dart';

import '../../shared/desktop_ui.dart';

/// How the desktop draws an item's type: its symbol in the OS's icon set,
/// the short name the table's Type column fits, and the tint of its type
/// tile ([DesktopTypeTile]).
///
/// An item whose type this version doesn't know (`type == null`) is drawn
/// as a generic file and named by its wire name.
extension DesktopItemType on Item {
  DesktopSymbol get typeSymbol => type.desktopSymbol;

  /// The full type name ("Android Keystore").
  String get typeLabel => type?.label ?? typeName;

  /// The type as the table's narrow Type column shows it ("Keystore").
  String get shortTypeLabel => switch (type) {
    ItemType.appleAuthKey => 'Auth key',
    ItemType.appleCertificate => 'Certificate',
    ItemType.provisioningProfile => 'Profile',
    ItemType.androidKeystore => 'Keystore',
    ItemType.firebaseConfig => 'Firebase',
    ItemType.gcpServiceAccount => 'Service account',
    ItemType.oauthClient => 'OAuth client',
    ItemType.sshKey => 'SSH key',
    ItemType.genericFile => 'File',
    ItemType.genericSecret => 'Secret',
    null => typeName,
  };
}

/// The same, for a type on its own (the import and editor sheets), where
/// `null` is a type this version doesn't know.
extension DesktopType on ItemType? {
  DesktopSymbol get desktopSymbol => switch (this) {
    ItemType.appleAuthKey => DesktopSymbol.typeAuthKey,
    ItemType.appleCertificate => DesktopSymbol.typeCertificate,
    ItemType.provisioningProfile => DesktopSymbol.typeProfile,
    ItemType.androidKeystore => DesktopSymbol.typeKeystore,
    ItemType.firebaseConfig => DesktopSymbol.typeFirebase,
    ItemType.gcpServiceAccount => DesktopSymbol.typeServiceAccount,
    ItemType.oauthClient => DesktopSymbol.typeOAuthClient,
    ItemType.sshKey => DesktopSymbol.typeSshKey,
    ItemType.genericSecret => DesktopSymbol.typeSecret,
    ItemType.genericFile || null => DesktopSymbol.typeFile,
  };

  /// The colour of the type tile, as on the phone's tiles.
  Color desktopTint(DesktopColors colors) => switch (this) {
    ItemType.appleAuthKey ||
    ItemType.gcpServiceAccount ||
    ItemType.oauthClient => colors.accentIcon,
    ItemType.provisioningProfile => colors.conflict,
    ItemType.androidKeystore => colors.success,
    ItemType.firebaseConfig => colors.warning,
    ItemType.appleCertificate || ItemType.sshKey => colors.text,
    ItemType.genericFile ||
    ItemType.genericSecret ||
    null => colors.secondaryText,
  };
}

/// The rounded square that marks an item's type on desktop (the inspector
/// header, the import and editor sheets, quick open): the type's symbol
/// from the OS's icon set on a light wash of its tint. Phones use bc_ui's
/// `TypeIconTile`.
class DesktopTypeTile extends StatelessWidget {
  const DesktopTypeTile({
    super.key,
    required this.type,
    this.size = DesktopMetrics.inspectorTileSize,
    this.selected = false,
    this.semanticLabel,
  });

  /// `null` for a type this version doesn't know: drawn as a generic file.
  final ItemType? type;

  /// Edge length. The symbol is half of it and the corners scale with it.
  final double size;

  /// On a selected row: drawn in the colour of its text.
  final bool selected;

  /// Read out instead of the type's label (an unknown type's wire name).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final tint = selected ? colors.onSelection : type.desktopTint(colors);
    // The inspector's 40 pt tile has a menu's corners, a little rounder.
    final radius =
        size *
        (DesktopMetrics.menuRadius + 2) /
        DesktopMetrics.inspectorTileSize;
    return Semantics(
      label: semanticLabel ?? type?.label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: selected ? 0.2 : 0.14),
          borderRadius: BorderRadius.all(Radius.circular(radius)),
        ),
        child: SizedBox.square(
          dimension: size,
          child: DesktopIcon(type.desktopSymbol, size: size / 2, color: tint),
        ),
      ),
    );
  }
}
