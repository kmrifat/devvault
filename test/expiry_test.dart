import 'dart:math';

import 'package:devvault/core/expiry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  Item item(DateTime? expiresAt, [ExpirySource? source]) => Item(
    id: '00000000-0000-4000-8000-000000000001',
    typeName: ItemType.appleCertificate.wireName,
    title: 'Distribution certificate',
    // A not_after fact that disagrees with expires_at: never consulted.
    fields: {
      'not_after': const ItemField(
        value: '2000-01-01T00:00:00Z',
        source: FieldSource.file,
      ),
    },
    expiresAt: expiresAt,
    expiresSource: expiresAt == null ? null : source ?? ExpirySource.file,
    createdAt: DateTime.utc(1999),
    updatedAt: DateTime.utc(1999),
    rev: Hlc.zero(testDeviceId),
    deviceId: testDeviceId,
  );

  ExpiryStatus at(DateTime? expiresAt, DateTime now) =>
      ExpiryStatus.of(item(expiresAt), now);

  group('the rule', () {
    final now = DateTime.utc(2026, 10, 7, 9);

    test('no expiry date is none, with no source', () {
      final status = at(null, now);
      expect(status.state, ExpiryState.none);
      expect(status.expiresAt, isNull);
      expect(status.source, isNull);
      expect(status.isUrgent, isFalse);
    });

    test('expired at the instant itself, soon for 30 × 24 h, then valid', () {
      ExpiryState state(Duration offset) => at(now.add(offset), now).state;
      expect(state(-const Duration(days: 400)), ExpiryState.expired);
      expect(state(-const Duration(seconds: 1)), ExpiryState.expired);
      expect(state(Duration.zero), ExpiryState.expired);
      expect(state(const Duration(microseconds: 1)), ExpiryState.soon);
      expect(state(const Duration(days: 30)), ExpiryState.soon);
      expect(
        state(const Duration(days: 30, microseconds: 1)),
        ExpiryState.valid,
      );
      expect(state(const Duration(days: 9000)), ExpiryState.valid);
    });

    test('the status carries where the date came from', () {
      final fromFile = ExpiryStatus.of(
        item(now.add(const Duration(days: 3)), ExpirySource.file),
        now,
      );
      final fromUser = ExpiryStatus.of(
        item(now.add(const Duration(days: 3)), ExpirySource.user),
        now,
      );
      expect(fromFile.source, ExpirySource.file);
      expect(fromUser.source, ExpirySource.user);
      expect(fromFile.state, fromUser.state);
      expect(fromFile, isNot(fromUser));
    });

    test('only expires_at counts, not facts or record dates', () {
      // The item carries a not_after fact from 2000 and was made in 1999;
      // with no expires_at it has no expiry at all.
      expect(at(null, now).state, ExpiryState.none);
    });

    test('ExpiryState.of agrees with ExpiryStatus', () {
      final x = item(now.add(const Duration(days: 12)));
      expect(ExpiryState.of(x, now), ExpiryStatus.of(x, now).state);
    });
  });

  group('time zones and daylight saving', () {
    test('the same instants give the same status in any offset', () {
      final expiry = DateTime.utc(2026, 11, 6, 9); // 30 days after `now`
      final nows = [
        DateTime.utc(2026, 10, 7, 9),
        DateTime.parse('2026-10-07T14:30:00+05:30'), // India
        DateTime.parse('2026-10-06T23:00:00-10:00'), // Hawaii
        DateTime.parse('2026-10-07T22:45:00+13:45'), // Chatham Islands
        DateTime.utc(2026, 10, 7, 9).toLocal(), // whatever this machine uses
      ];
      for (final now in nows) {
        final status = at(expiry, now);
        expect(status.state, ExpiryState.soon, reason: '$now');
        expect(status.expiresAt, expiry);
        expect(status.expiresAt!.isUtc, isTrue);
        expect(daysLeft(expiry, now), '30 days', reason: '$now');
      }
      // An expiry written with an offset is the same instant.
      expect(
        at(DateTime.parse('2026-11-06T10:00:00+01:00'), nows.first),
        at(expiry, nows.first),
      );
    });

    // Windows that span a clock change: the US (8 Mar, 1 Nov 2026), the EU
    // (29 Mar, 25 Oct 2026) and Lord Howe Island's half-hour shift (5 Apr
    // 2026). 30 days stays 720 hours; nothing is counted in local days.
    final changes = {
      'US spring forward': DateTime.utc(2026, 3, 8, 10),
      'US fall back': DateTime.utc(2026, 11, 1, 6),
      'EU spring forward': DateTime.utc(2026, 3, 29, 1),
      'EU fall back': DateTime.utc(2026, 10, 25, 1),
      'Lord Howe': DateTime.utc(2026, 4, 4, 15),
    };
    for (final MapEntry(key: name, value: change) in changes.entries) {
      test('a window across the $name change is 720 hours', () {
        final now = change.subtract(const Duration(days: 10));
        final edge = now.add(const Duration(hours: 720));
        expect(at(edge, now).state, ExpiryState.soon);
        expect(
          at(edge.add(const Duration(seconds: 1)), now).state,
          ExpiryState.valid,
        );
        expect(daysLeft(edge, now), '30 days');
        expect(daysLeft(change.add(const Duration(hours: 1)), now), '11 days');
      });
    }

    test('random instants: the offset never changes the answer', () {
      final random = Random(0x0E4);
      for (var i = 0; i < 2000; i++) {
        final now = DateTime.utc(2026)
            .add(Duration(minutes: random.nextInt(3 * 365 * 24 * 60)));
        final expiry = now.add(
          Duration(minutes: random.nextInt(120 * 24 * 60) - 60 * 24 * 60),
        );
        final reference = at(expiry, now);
        for (final offsetMinutes in const [-600, -210, 0, 330, 525, 825]) {
          final shifted = DateTime.parse(
            _withOffset(now, Duration(minutes: offsetMinutes)),
          );
          expect(shifted, now);
          expect(at(expiry, shifted), reference);
          expect(daysLeft(expiry, shifted), daysLeft(expiry, now));
        }
      }
    });
  });
}

/// [utc] written as wall-clock time at [offset], e.g. `…T14:30:00+05:30`.
String _withOffset(DateTime utc, Duration offset) {
  final wall = utc.add(offset);
  String two(int n) => n.toString().padLeft(2, '0');
  final sign = offset.isNegative ? '-' : '+';
  final o = offset.abs();
  return '${wall.year}-${two(wall.month)}-${two(wall.day)}T'
      '${two(wall.hour)}:${two(wall.minute)}:${two(wall.second)}'
      '$sign${two(o.inHours)}:${two(o.inMinutes % 60)}';
}
