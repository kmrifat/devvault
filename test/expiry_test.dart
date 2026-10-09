import 'dart:math';

import 'package:devvault/core/expiry.dart';
import 'package:devvault/features/expiry/desktop_expiry_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

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

  group('days left', () {
    final now = DateTime.utc(2026, 10, 9, 15, 20);
    String left(Duration d) => daysLeft(now.add(d), now);

    test('round 24-hour spans up', () {
      expect(left(const Duration(seconds: 30)), '1 day');
      expect(left(const Duration(hours: 1)), '1 day');
      expect(left(const Duration(hours: 12)), '1 day');
      expect(left(const Duration(days: 1)), '1 day');
      expect(left(const Duration(days: 1, microseconds: 1)), '2 days');
      expect(left(const Duration(days: 29, hours: 23)), '30 days');
      expect(left(const Duration(days: 30)), '30 days');
    });

    test('in coarser units from 60 days on', () {
      String time(Duration d) => timeLeft(now.add(d), now);
      expect(time(const Duration(days: 1)), '1 day');
      expect(time(const Duration(days: 30, hours: 1)), '31 days');
      expect(time(const Duration(days: 59)), '59 days');
      expect(time(const Duration(days: 60)), '2 months');
      expect(time(const Duration(days: 729)), '24 months');
      expect(time(const Duration(days: 730)), '2 years');
    });
  });

  group('days ago (WALK-03)', () {
    // Local wall-clock times, so these hold in whatever zone runs them.
    final oct6 = [
      DateTime(2026, 10, 6),
      DateTime(2026, 10, 6, 9, 30),
      DateTime(2026, 10, 6, 23, 59, 59),
    ];
    final oct9 = [
      DateTime(2026, 10, 9),
      DateTime(2026, 10, 9, 0, 1),
      DateTime(2026, 10, 9, 12),
      DateTime(2026, 10, 9, 23, 59, 59),
    ];

    test('expired on Oct 6 is 3 days ago all through Oct 9', () {
      for (final expired in oct6) {
        for (final now in oct9) {
          expect(daysSince(expired, now), 3, reason: '$expired → $now');
          expect(timeAgo(expired, now), '3 days ago');
          expect(DesktopExpiryTable.left(expired, now), '3 days ago');
          // The same instants written in UTC.
          expect(timeAgo(expired.toUtc(), now.toUtc()), '3 days ago');
        }
      }
    });

    test('today, then yesterday from local midnight', () {
      final expired = DateTime(2026, 10, 9, 8);
      expect(timeAgo(expired, expired), 'today');
      expect(timeAgo(expired, DateTime(2026, 10, 9, 8, 1)), 'today');
      expect(timeAgo(expired, DateTime(2026, 10, 9, 23, 59, 59)), 'today');
      expect(DesktopExpiryTable.left(expired, expired), 'today');
      expect(timeAgo(expired, DateTime(2026, 10, 10)), '1 day ago');
      expect(timeAgo(expired, DateTime(2026, 10, 10, 23, 59)), '1 day ago');
      // Two minutes apart, either side of midnight: yesterday.
      expect(
        timeAgo(DateTime(2026, 10, 8, 23, 59), DateTime(2026, 10, 9, 0, 1)),
        '1 day ago',
      );
      expect(timeAgo(expired, DateTime(2026, 10, 11)), '2 days ago');
    });

    test('across months and years, in coarser units from 60 days', () {
      expect(
        timeAgo(DateTime(2026, 9, 30, 23), DateTime(2026, 10, 1)),
        '1 day ago',
      );
      expect(
        timeAgo(DateTime(2025, 12, 31, 23), DateTime(2026, 1, 1, 1)),
        '1 day ago',
      );
      expect(daysSince(DateTime(2028, 2, 28), DateTime(2028, 3, 1)), 2);
      expect(
        timeAgo(DateTime(2026, 8, 10), DateTime(2026, 10, 9)),
        '2 months ago',
      );
      expect(
        timeAgo(DateTime(2024, 10, 9), DateTime(2026, 10, 9)),
        '2 years ago',
      );
    });

    test('counts the dates in the zone, not 24-hour spans', () {
      final dhaka = tz.getLocation('Asia/Dhaka'); // +06:00
      final honolulu = tz.getLocation('Pacific/Honolulu'); // -10:00
      final kiritimati = tz.getLocation('Pacific/Kiritimati'); // +14:00
      // A date the user picked, kept as midnight UTC.
      final picked = DateTime.utc(2026, 10, 6);
      int since(DateTime expired, tz.Location zone, int hour, [int min = 0]) =>
          calendarDaysBetween(
            tz.TZDateTime.from(expired, zone),
            tz.TZDateTime(zone, 2026, 10, 9, hour, min),
          );
      for (final (hour, min) in const [
        (0, 0),
        (5, 59),
        (6, 0),
        (12, 0),
        (23, 59),
      ]) {
        // Oct 6, 06:00 in Dhaka: 3 days on Oct 9, whatever the time.
        expect(since(picked, dhaka, hour, min), 3, reason: '$hour:$min');
        // Oct 6, 14:00 there.
        expect(since(picked, kiritimati, hour, min), 3, reason: '$hour:$min');
        // Oct 5, 14:00 in Honolulu, the date shown there: 4 days.
        expect(since(picked, honolulu, hour, min), 4, reason: '$hour:$min');
      }
      // Late on Oct 6 in Honolulu is already Oct 7 in UTC: still 3 there.
      final late = tz.TZDateTime(honolulu, 2026, 10, 6, 23).toUtc();
      expect(since(late, honolulu, 0), 3);
      expect(since(late, dhaka, 0), 2);
    });

    test('a daylight-saving change between makes no difference', () {
      final berlin = tz.getLocation('Europe/Berlin');
      tz.TZDateTime at(int m, int d, int h, [int min = 0]) =>
          tz.TZDateTime(berlin, 2026, m, d, h, min);
      // EU fall back, 25 Oct: a 25-hour day.
      expect(calendarDaysBetween(at(10, 24, 23, 30), at(10, 26, 0, 30)), 2);
      expect(calendarDaysBetween(at(10, 25, 0, 30), at(10, 25, 23, 30)), 0);
      // EU spring forward, 29 Mar: a 23-hour day.
      expect(calendarDaysBetween(at(3, 28, 23, 30), at(3, 29, 23, 30)), 1);
      expect(calendarDaysBetween(at(3, 28, 0), at(3, 30, 23, 59)), 2);
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
