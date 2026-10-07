import 'package:flutter/foundation.dart' show immutable;
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

  static ExpiryState of(Item item, DateTime now) =>
      ExpiryStatus.of(item, now).state;
}

/// An item's expiry, worked out from `expires_at` alone, together with
/// where that date came from.
///
/// The rules compare instants and nothing else: expired when `expires_at`
/// is not after now, expiring soon within the next 30 × 24 hours
/// (inclusive), valid after that. No calendar arithmetic is involved, so
/// the answer is the same in every time zone and on either side of a
/// daylight-saving change. No other date (a certificate's notAfter fact,
/// when the item was made) is ever used: only what `expires_at` says, and
/// it only says what the file or the user said.
@immutable
class ExpiryStatus {
  const ExpiryStatus._(this.state, this.expiresAt, this.source);

  /// The status of [item] at [now].
  factory ExpiryStatus.of(Item item, DateTime now) =>
      ExpiryStatus.at(item.expiresAt, item.expiresSource, now);

  /// The pure rule: [expiresAt] with its [source], at [now].
  factory ExpiryStatus.at(
    DateTime? expiresAt,
    ExpirySource? source,
    DateTime now,
  ) {
    if (expiresAt == null) {
      return const ExpiryStatus._(ExpiryState.none, null, null);
    }
    final at = expiresAt.toUtc();
    final state = !at.isAfter(now)
        ? ExpiryState.expired
        : at.difference(now) <= ExpiryState.expiryWindow
        ? ExpiryState.soon
        : ExpiryState.valid;
    return ExpiryStatus._(state, at, source);
  }

  final ExpiryState state;

  /// The expiry instant, in UTC; `null` when [state] is
  /// [ExpiryState.none].
  final DateTime? expiresAt;

  /// Where [expiresAt] came from: the file or the user. `null` only when
  /// there is no expiry.
  final ExpirySource? source;

  /// Whether the item needs attention: expired or expiring soon.
  bool get isUrgent =>
      state == ExpiryState.expired || state == ExpiryState.soon;

  @override
  bool operator ==(Object other) =>
      other is ExpiryStatus &&
      other.state == state &&
      other.expiresAt == expiresAt &&
      other.source == source;

  @override
  int get hashCode => Object.hash(state, expiresAt, source);

  @override
  String toString() =>
      'ExpiryStatus(${state.name}, ${expiresAt?.toIso8601String()}, '
      '${source?.wireName})';
}

/// Expiry counts for the sidebar and the expiry dashboard.
extension ExpiryCounts on VaultIndex {
  int countExpiring(ExpiryState state, DateTime now) =>
      byExpiry.where((i) => ExpiryState.of(i, now) == state).length;
}

/// "1 day", "12 days": whole days left, rounded up. Days are 24-hour
/// spans counted from [now], so a daylight-saving change in between
/// doesn't move the count.
String daysLeft(DateTime expiresAt, DateTime now) {
  final days = (expiresAt.difference(now).inMinutes / (24 * 60)).ceil();
  return days == 1 ? '1 day' : '$days days';
}
