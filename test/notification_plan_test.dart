import 'dart:convert';
import 'dart:math';

import 'package:devvault/core/notification_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late tz.Location berlin;
  late tz.Location newYork;
  setUp(() {
    berlin = tz.getLocation('Europe/Berlin');
    newYork = tz.getLocation('America/New_York');
  });

  var n = 0;
  Item item(DateTime? expiresAt, {String? id, String title = 'Cert'}) => Item(
    id: id ?? '00000000-0000-4000-8000-${(++n).toString().padLeft(12, '0')}',
    typeName: ItemType.appleCertificate.wireName,
    title: title,
    expiresAt: expiresAt,
    expiresSource: expiresAt == null ? null : ExpirySource.file,
    createdAt: testNow,
    updatedAt: testNow,
    rev: Hlc.zero(testDeviceId),
    deviceId: testDeviceId,
  );

  String local(tz.TZDateTime t) => t.toIso8601String().substring(0, 16);

  group('planAlerts', () {
    final now = DateTime.utc(2026, 10, 7, 9); // 11:00 in Berlin

    test('two reminders at 09:00 local: entering the window, and the day', () {
      final x = item(DateTime.utc(2027, 1, 20, 15), title: 'Push cert');
      final plan = planAlerts([x], now, berlin, AlertLedger());
      expect(plan, hasLength(2));
      final window = plan.firstWhere((a) => a.kind == ExpiryAlertKind.window);
      final day = plan.firstWhere((a) => a.kind == ExpiryAlertKind.expiryDay);
      // Enters the window 2026-12-21 15:00Z = 16:00 Berlin → next 09:00.
      expect(local(window.fireAt), '2026-12-22T09:00');
      expect(local(day.fireAt), '2027-01-20T09:00');
      expect(window.title, '“Push cert” expires soon');
      expect(window.body, 'It expires on Jan 20, 2027.');
      expect(day.title, '“Push cert” expires today');
      expect(day.body, 'It expires at 16:00 today.');
    });

    test('09:00 is local wall time on both sides of a DST change', () {
      // Window in Berlin summer time, expiry in winter time.
      final x = item(DateTime.utc(2026, 11, 20, 12));
      final plan = planAlerts([x], now, berlin, AlertLedger());
      for (final alert in plan) {
        expect(alert.fireAt.hour, 9);
        expect(alert.fireAt.minute, 0);
      }
      final utcHours = {for (final a in plan) a.fireAt.toUtc().hour};
      expect(utcHours, {7, 8}); // CEST then CET

      final ny = planAlerts([x], now, newYork, AlertLedger());
      expect(ny.map((a) => a.fireAt.hour).toSet(), {9});
    });

    test('the expiry day is the local calendar day', () {
      // 2026-11-20 02:00Z is still 19 Nov in New York.
      final x = item(DateTime.utc(2026, 11, 20, 2));
      final day = planAlerts(
        [x],
        now,
        newYork,
        AlertLedger(),
      ).firstWhere((a) => a.kind == ExpiryAlertKind.expiryDay);
      expect(local(day.fireAt), '2026-11-19T09:00');
      // In Berlin it's the 20th, already expired by 09:00.
      final berlinDay = planAlerts(
        [x],
        now,
        berlin,
        AlertLedger(),
      ).firstWhere((a) => a.kind == ExpiryAlertKind.expiryDay);
      expect(local(berlinDay.fireAt), '2026-11-20T09:00');
      expect(berlinDay.title, endsWith('has expired'));
      expect(berlinDay.body, 'It expired at 03:00 today.');
    });

    test('already inside the window: the next 09:00, if before the day', () {
      final soon = item(DateTime.utc(2026, 10, 19, 12));
      final plan = planAlerts([soon], now, berlin, AlertLedger());
      expect(plan.map((a) => '${a.kind.wireName} ${local(a.fireAt)}'), [
        'window 2026-10-08T09:00',
        'expiry_day 2026-10-19T09:00',
      ]);

      // Expiring tomorrow: the window reminder would land on the same
      // morning as the day one (or after), so only the day one is kept.
      final tomorrow = item(DateTime.utc(2026, 10, 8, 18));
      expect(
        planAlerts([tomorrow], now, berlin, AlertLedger()).map((a) => a.kind),
        [ExpiryAlertKind.expiryDay],
      );
    });

    test('nothing in the past, nothing for items without a date', () {
      final expired = item(DateTime.utc(2026, 10, 1));
      final today = item(DateTime.utc(2026, 10, 7, 20)); // 09:00 passed
      final none = item(null);
      expect(
        planAlerts([expired, today, none], now, berlin, AlertLedger()),
        isEmpty,
      );
    });

    test('nothing already delivered', () {
      final x = item(DateTime.utc(2027, 1, 20, 15));
      final ledger = AlertLedger(
        delivered: {
          x.id: {ExpiryAlertKind.window},
        },
      );
      expect(planAlerts([x], now, berlin, ledger).map((a) => a.kind), [
        ExpiryAlertKind.expiryDay,
      ]);
    });

    test('ids are deterministic, distinct per kind and 31-bit', () {
      final id = '9b2f7a4e-1c3d-4e5f-8a6b-7c8d9e0f1a2b';
      final a = alertId(id, ExpiryAlertKind.window);
      expect(alertId(id, ExpiryAlertKind.window), a);
      expect(alertId(id, ExpiryAlertKind.expiryDay), isNot(a));
      final random = Random(7);
      final seen = <int>{};
      for (var i = 0; i < 5000; i++) {
        final uuid = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        for (final kind in ExpiryAlertKind.values) {
          final v = alertId(uuid, kind);
          expect(v, inInclusiveRange(0, 0x7fffffff));
          expect(seen.add(v), isTrue, reason: 'collision');
        }
      }
    });
  });

  group('syncAlerts and the ledger', () {
    final now = DateTime.utc(2026, 10, 7, 9);

    test('schedules once; the same plan again changes nothing', () {
      final x = item(DateTime.utc(2027, 1, 20, 15));
      final ledger = AlertLedger();
      final first = syncAlerts(ledger, [x], now, berlin);
      expect(first.schedule, hasLength(2));
      expect(first.cancel, isEmpty);
      final again = syncAlerts(ledger, [x], now, berlin);
      expect(again.isEmpty, isTrue);
    });

    test('a moved date reschedules under the same ids', () {
      final x = item(DateTime.utc(2027, 1, 20, 15));
      final ledger = AlertLedger();
      final first = syncAlerts(ledger, [x], now, berlin);
      final moved = x.copyWith(expiresAt: DateTime.utc(2027, 3, 1, 12));
      final changes = syncAlerts(ledger, [moved], now, berlin);
      expect(changes.cancel, isEmpty);
      expect(
        changes.schedule.map((a) => a.id).toSet(),
        first.schedule.map((a) => a.id).toSet(),
      );
    });

    test('a removed date cancels what was scheduled', () {
      final x = item(DateTime.utc(2027, 1, 20, 15));
      final ledger = AlertLedger();
      syncAlerts(ledger, [x], now, berlin);
      final cleared = item(null, id: x.id);
      final changes = syncAlerts(ledger, [cleared], now, berlin);
      expect(changes.schedule, isEmpty);
      expect(changes.cancel.toSet(), {
        alertId(x.id, ExpiryAlertKind.window),
        alertId(x.id, ExpiryAlertKind.expiryDay),
      });
      expect(ledger.scheduled, isEmpty);
    });

    test('a passed time counts as delivered and is never planned again', () {
      final x = item(DateTime.utc(2026, 10, 19, 12));
      final ledger = AlertLedger();
      syncAlerts(ledger, [x], now, berlin);
      final later = DateTime.utc(2026, 10, 8, 12); // window fired at 07:00Z
      syncAlerts(ledger, [x], later, berlin);
      expect(ledger.wasDelivered(x.id, ExpiryAlertKind.window), isTrue);
      // The user moves the date out again: no second window reminder.
      final edited = x.copyWith(expiresAt: DateTime.utc(2026, 10, 30, 12));
      expect(planAlerts([edited], later, berlin, ledger).map((a) => a.kind), [
        ExpiryAlertKind.expiryDay,
      ]);
    });

    test('reset (a replaced file) lets the item warn again', () {
      final x = item(DateTime.utc(2026, 10, 19, 12));
      final ledger = AlertLedger(
        delivered: {
          x.id: {ExpiryAlertKind.window, ExpiryAlertKind.expiryDay},
        },
      );
      expect(planAlerts([x], now, berlin, ledger), isEmpty);
      ledger.reset(x.id);
      expect(planAlerts([x], now, berlin, ledger), hasLength(2));
    });

    test('deleted items are forgotten and their reminders cancelled', () {
      final x = item(DateTime.utc(2027, 1, 20, 15));
      final ledger = AlertLedger();
      syncAlerts(ledger, [x], now, berlin);
      final cancel = forgetMissing(ledger, {});
      expect(cancel, hasLength(2));
      expect(ledger.scheduled, isEmpty);
      expect(ledger.delivered, isEmpty);
    });

    test('round-trips through JSON, and junk reads as empty', () {
      final x = item(DateTime.utc(2027, 1, 20, 15));
      final ledger = AlertLedger(
        delivered: {
          'gone': {ExpiryAlertKind.window},
        },
      );
      syncAlerts(ledger, [x], now, berlin);
      final copy = AlertLedger.fromJson(
        jsonDecode(jsonEncode(ledger.toJson())),
      );
      expect(jsonEncode(copy.toJson()), jsonEncode(ledger.toJson()));
      expect(jsonEncode(ledger.toJson()), isNot(contains('Cert')));
      for (final junk in [
        null,
        1,
        'x',
        {},
        {'version': 2},
        {'items': []},
      ]) {
        expect(AlertLedger.fromJson(junk).delivered, isEmpty);
      }
    });
  });

  test('provably at most 2 per item, one of each kind, across restarts '
      'and edits', () {
    final random = Random(0x403);
    final zones = [berlin, newYork, tz.getLocation('Australia/Lord_Howe')];
    for (var run = 0; run < 60; run++) {
      final location = zones[run % zones.length];
      var now = DateTime.utc(
        2026,
        1,
        1,
      ).add(Duration(hours: random.nextInt(24 * 365)));
      var items = [
        for (var i = 0; i < 6; i++)
          item(
            random.nextBool()
                ? now.add(Duration(hours: random.nextInt(24 * 90)))
                : null,
          ),
      ];
      // The OS: what it holds and what it showed.
      final pending = <int, (String, ExpiryAlertKind, DateTime)>{};
      final shown = <String, List<ExpiryAlertKind>>{};
      var json = jsonEncode(AlertLedger().toJson());

      for (var step = 0; step < 80; step++) {
        // Time passes; the OS fires whatever is due.
        now = now.add(Duration(hours: 1 + random.nextInt(36)));
        for (final MapEntry(key: id, value: (itemId, kind, at))
            in pending.entries.toList()) {
          if (!at.isAfter(now)) {
            (shown[itemId] ??= []).add(kind);
            pending.remove(id);
          }
        }
        // Sometimes the user edits a date, adds or removes one.
        if (random.nextInt(3) == 0) {
          final i = random.nextInt(items.length);
          final x = items[i];
          final date = random.nextInt(4) == 0
              ? null
              : now.add(Duration(hours: random.nextInt(24 * 60) - 24 * 5));
          items[i] = date == null
              ? item(null, id: x.id)
              : x.copyWith(expiresAt: date, expiresSource: ExpirySource.user);
        }
        // A restart: the ledger comes back from disk.
        final ledger = AlertLedger.fromJson(jsonDecode(json));
        final changes = syncAlerts(ledger, items, now, location);
        for (final id in changes.cancel) {
          pending.remove(id);
        }
        for (final a in changes.schedule) {
          expect(a.fireAt.isAfter(now), isTrue);
          pending[a.id] = (a.itemId, a.kind, a.fireAt.toUtc());
        }
        json = jsonEncode(ledger.toJson());
      }
      for (final MapEntry(key: itemId, value: kinds) in shown.entries) {
        expect(kinds.length, lessThanOrEqualTo(2), reason: itemId);
        expect(kinds.toSet().length, kinds.length, reason: '$itemId $kinds');
      }
    }
  });
}
