import '../data/vault_session.dart';
import 'routes.dart';

/// Where the router sends the user for the current [session].
///
/// - No vault: only *create*.
/// - Locked: only *unlock* and *recover*; anything else bounces to unlock
///   and comes back afterwards (`?from=`).
/// - Unlocked with a new recovery key not yet confirmed: only the recovery
///   kit (D02), so the key is never skipped.
/// - Unlocked: lock screens forward to where the user was going, or the
///   vault.
///
/// Returns `null` to stay.
String? sessionRedirect(
  VaultSession session,
  Uri location, {
  required bool recoveryKitPending,
}) {
  final path = location.path;
  switch (session) {
    case NoVault():
      return path == Routes.create ? null : Routes.create;

    case Locked():
      if (path == Routes.unlock || path == Routes.recover) return null;
      if (_isEntry(path)) return Routes.unlock;
      return Uri(
        path: Routes.unlock,
        queryParameters: {'from': location.toString()},
      ).toString();

    case Unlocked():
      if (recoveryKitPending) {
        return path == Routes.createRecoveryKit
            ? null
            : Routes.createRecoveryKit;
      }
      if (_isEntry(path)) {
        final from = location.queryParameters['from'];
        return _isSafeReturn(from) ? from : Routes.vault();
      }
      return null;
  }
}

/// Screens that only make sense before the vault is open.
bool _isEntry(String path) =>
    path == Routes.unlock ||
    path == Routes.recover ||
    path == Routes.create ||
    path == Routes.createRecoveryKit;

/// A `from` worth returning to: an in-app path that isn't itself an entry
/// screen.
bool _isSafeReturn(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return false;
  }
  return !_isEntry(Uri.parse(from).path);
}
