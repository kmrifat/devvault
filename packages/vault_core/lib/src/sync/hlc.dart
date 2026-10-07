import 'package:meta/meta.dart';

import '../format/envelope.dart';
import '../format/format_error.dart';

/// A hybrid logical clock value: the `rev` on every record (SPEC §7).
///
/// Ordered by wall time, then counter, then device id, so comparing the
/// string forms gives the same order as [compareTo].
@immutable
class Hlc implements Comparable<Hlc> {
  Hlc(this.wallMs, this.counter, this.deviceId) {
    if (wallMs < 0 || wallMs > maxWallMs) {
      throw ArgumentError.value(wallMs, 'wallMs');
    }
    if (counter < 0 || counter > maxCounter) {
      throw ArgumentError.value(counter, 'counter');
    }
    if (!isCanonicalUuid(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'not a lowercase UUID');
    }
  }

  /// The zero clock for [deviceId], before any write.
  Hlc.zero(String deviceId) : this(0, 0, deviceId);

  static const int maxWallMs = 999999999999999; // 15 digits
  static const int maxCounter = 99999; // 5 digits

  /// Remote clocks this far ahead are accepted but reported: they point at
  /// a device with a wrong clock.
  static const Duration maxDrift = Duration(hours: 24);

  final int wallMs;
  final int counter;
  final String deviceId;

  /// `001759827600000-00000-<device_id>`.
  @override
  String toString() =>
      '${wallMs.toString().padLeft(15, '0')}-'
      '${counter.toString().padLeft(5, '0')}-$deviceId';

  static final RegExp _pattern = RegExp(r'^(\d{15})-(\d{5})-(.+)$');

  static Hlc parse(Object? value) {
    final match = value is String ? _pattern.firstMatch(value) : null;
    if (match == null) {
      throw const VaultFormatException('rev is not a hybrid logical clock');
    }
    try {
      return Hlc(int.parse(match[1]!), int.parse(match[2]!), match[3]!);
    } on ArgumentError {
      throw const VaultFormatException('rev is not a hybrid logical clock');
    }
  }

  /// The next local tick at wall time [now]: later than this clock and
  /// never earlier than [now].
  Hlc tick(DateTime now) {
    final physical = now.millisecondsSinceEpoch;
    if (physical > wallMs) return Hlc(physical, 0, deviceId);
    return _bump(wallMs, counter + 1);
  }

  /// This device's clock after seeing [remote] at wall time [now]: later
  /// than both this clock and [remote].
  Hlc receive(Hlc remote, DateTime now) {
    final physical = now.millisecondsSinceEpoch;
    final wall = [
      wallMs,
      remote.wallMs,
      physical,
    ].reduce((a, b) => a > b ? a : b);
    final int next;
    if (wall == wallMs && wall == remote.wallMs) {
      next = (counter > remote.counter ? counter : remote.counter) + 1;
    } else if (wall == wallMs) {
      next = counter + 1;
    } else if (wall == remote.wallMs) {
      next = remote.counter + 1;
    } else {
      next = 0;
    }
    return _bump(wall, next);
  }

  /// Whether [remote] claims a time more than [maxDrift] past [now].
  static bool isTooFarAhead(Hlc remote, DateTime now) =>
      remote.wallMs - now.millisecondsSinceEpoch > maxDrift.inMilliseconds;

  Hlc _bump(int wall, int nextCounter) => nextCounter > maxCounter
      ? Hlc(wall + 1, 0, deviceId) // counter overflow: borrow 1 ms
      : Hlc(wall, nextCounter, deviceId);

  @override
  int compareTo(Hlc other) {
    if (wallMs != other.wallMs) return wallMs.compareTo(other.wallMs);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return deviceId.compareTo(other.deviceId);
  }

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >(Hlc other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.wallMs == wallMs &&
      other.counter == counter &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(wallMs, counter, deviceId);
}
