import 'package:vault_core/vault_core.dart';

import '../../shared/desktop_ui.dart';

/// How the desktop vault table and inspector draw an item's type: its
/// symbol in the OS's icon set, the short name the table's Type column
/// fits, and the tint of the inspector's type tile.
///
/// An item whose type this version doesn't know (`type == null`) is drawn
/// as a generic file and named by its wire name.
extension DesktopItemType on Item {
  DesktopSymbol get typeSymbol => switch (type) {
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

  /// The colour of the inspector's type tile, as on the phone's tiles.
  Color typeTint(DesktopColors colors) => switch (type) {
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
