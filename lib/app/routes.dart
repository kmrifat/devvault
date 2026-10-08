/// Every path in the app. Screens navigate with these, never with literals:
///
/// ```dart
/// context.go(Routes.vault(app: appId, env: 'production'));
/// context.push(Routes.item(id));
/// ```
abstract final class Routes {
  // Lock screens and first run
  static const unlock = '/unlock';
  static const create = '/create';
  static const createRecoveryKit = '/create/recovery-kit';

  /// Join a vault that already syncs to a bucket (P2-10).
  static const joinVault = '/create/join';
  static const recover = '/recover';

  // Shell branches (sidebar on desktop, bottom nav on mobile)
  static const vaultRoot = '/vault';
  static const expiry = '/expiry';
  static const settings = '/settings';

  // Settings sections
  static const settingsSync = '/settings/sync';
  static const settingsSecurity = '/settings/security';
  static const settingsAgents = '/settings/agents';

  // Device pairing (QR, P4)
  static const pair = '/pair';

  /// The vault, optionally filtered and with an item selected.
  ///
  /// On desktop the selected [item] opens in the detail pane; on mobile use
  /// [Routes.item] to push the item screen instead.
  static String vault({
    String? item,
    String? app,
    String? platform,
    String? env,
    String? tag,
    String? view,
    String? kind,
    String? q,
  }) {
    final query = <String, String>{
      'item': ?item,
      'app': ?app,
      'platform': ?platform,
      'env': ?env,
      'tag': ?tag,
      'view': ?view,
      'kind': ?kind,
      'q': ?q,
    };
    return Uri(
      path: vaultRoot,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  /// The expiry dashboard, opened on the expired section when [expired].
  static String expiryShowing({bool expired = false}) =>
      expired ? '$expiry?show=expired' : expiry;

  /// A single item as its own screen (mobile). On desktop this redirects to
  /// [vault] with the item selected.
  static String item(String id) => '/vault/item/$id';
}
