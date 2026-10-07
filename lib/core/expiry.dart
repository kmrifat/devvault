import 'package:vault_core/vault_core.dart';

/// How close an item is to its expiry date.
enum ExpiryState {
  /// No expiry date.
  none,

  /// Expires more than [expiryWindow] from now.
  valid,

  /// Expires within [expiryWindow].
  soon,

  /// Already expired.
  expired;

  /// Items expiring within this window count as "expiring soon".
  static const expiryWindow = Duration(days: 30);

  static ExpiryState of(Item item, DateTime now) {
    final expiresAt = item.expiresAt;
    if (expiresAt == null) return none;
    if (!expiresAt.isAfter(now)) return expired;
    if (expiresAt.difference(now) <= expiryWindow) return soon;
    return valid;
  }
}

/// Expiry counts for the sidebar and the expiry dashboard.
extension ExpiryCounts on VaultIndex {
  int countExpiring(ExpiryState state, DateTime now) =>
      byExpiry.where((i) => ExpiryState.of(i, now) == state).length;
}
