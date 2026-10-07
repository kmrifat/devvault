import 'dart:convert';
import 'dart:io';

import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/notification_plan.dart';
import 'package:devvault/data/app_settings.dart';
import 'package:devvault/data/expiry_alerts.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/services/notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

/// The OS, as far as the app can tell: what's pending, and what was asked.
class FakeScheduler implements AlertScheduler {
  FakeScheduler(this.location);

  @override
  final tz.Location location;

  final pending = <int, PlannedAlert>{};
  final cancelled = <int>[];
  int scheduleCalls = 0;
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> schedule(PlannedAlert alert) async {
    scheduleCalls++;
    pending[alert.id] = alert;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.remove(id);
  }
}

void main() {
  setUpAll(() async {
    tzdata.initializeTimeZones();
    await loadTestCrypto();
  });

  group('AlertLedgerFile', () {
    test('saves atomically and reads back; junk reads as empty', () {
      final dir = Directory.systemTemp.createTempSync('ledger_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = AlertLedgerFile(dir);
      expect(file.load().delivered, isEmpty); // no file yet

      final ledger = AlertLedger(
        delivered: {
          'a': {ExpiryAlertKind.window},
        },
        scheduled: {
          'b': {ExpiryAlertKind.expiryDay: DateTime.utc(2027)},
        },
      );
      file.save(ledger);
      expect(File('${dir.path}/notifications.json.tmp').existsSync(), isFalse);
      expect(jsonEncode(file.load().toJson()), jsonEncode(ledger.toJson()));

      File('${dir.path}/notifications.json').writeAsStringSync('{nope');
      expect(file.load().scheduled, isEmpty);
    });
  });

  test('withdrawAlerts cancels what is pending, keeps what fired', () {
    final now = DateTime.utc(2026, 10, 7);
    final ledger = AlertLedger(
      scheduled: {
        'a': {
          ExpiryAlertKind.window: DateTime.utc(2026, 10, 1),
          ExpiryAlertKind.expiryDay: DateTime.utc(2026, 11, 1),
        },
      },
    );
    expect(withdrawAlerts(ledger, now), [
      alertId('a', ExpiryAlertKind.expiryDay),
    ]);
    expect(ledger.scheduled, isEmpty);
    expect(ledger.wasDelivered('a', ExpiryAlertKind.window), isTrue);
    expect(ledger.wasDelivered('a', ExpiryAlertKind.expiryDay), isFalse);
  });

  test('the setting round-trips and defaults to on', () {
    expect(const AppSettings().expiryReminders, isTrue);
    expect(AppSettings.fromJson({}).expiryReminders, isTrue);
    final off = const AppSettings().copyWith(expiryReminders: false);
    expect(AppSettings.fromJson(off.toJson()).expiryReminders, isFalse);
  });

  group('ExpiryAlerts in the app', () {
    late FakeScheduler os;

    Future<void> open(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1440, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      os = FakeScheduler(tz.getLocation('Europe/Berlin'));
      await pumpUnlockedApp(
        tester,
        location: Routes.vault(),
        vault: TestVault.sample,
        layout: AppLayout.desktop,
        overrides: [
          alertSchedulerProvider.overrideWithValue(os),
          alertDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 50),
          ),
        ],
      );
    }

    VaultIndex index(WidgetTester tester) =>
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

    /// Lets the debounce run out and the sync finish. Vault writes happen
    /// in runAsync, so the debounce timer runs on the real clock while the
    /// sync's own steps run on the test's: alternate the two until it's
    /// done.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
    }

    AlertLedger ledger(WidgetTester tester) =>
        appContainer(tester).read(alertLedgerFileProvider).load();

    String describe(PlannedAlert a) =>
        '${a.title} @ ${a.fireAt.toIso8601String().substring(0, 16)}';

    testWidgets('schedules the sample vault’s reminders once, after a pause', (
      tester,
    ) async {
      await open(tester);
      // Debounced: nothing yet.
      expect(os.pending, isEmpty);
      await settle(tester);

      // Expired 3 days ago: nothing. 12 and 20 days out: both reminders
      // (the window one tomorrow morning). 2051: both, decades away; it
      // expires at 01:00 Berlin time, so by 09:00 that day it has.
      expect(os.pending.values.map(describe).toList()..sort(), [
        '“App Store profile” expires soon @ 2026-10-08T09:00',
        '“App Store profile” expires today @ 2026-10-27T09:00',
        '“Play publisher” expires soon @ 2026-10-08T09:00',
        '“Play publisher” expires today @ 2026-10-19T09:00',
        '“Upload keystore” expires soon @ 2050-12-15T09:00',
        '“Upload keystore” has expired @ 2051-01-14T09:00',
      ]);
      expect(os.permissionRequests, 1);
      expect(ledger(tester).scheduled, hasLength(3));

      // Nothing changed: syncing again schedules nothing.
      final calls = os.scheduleCalls;
      await appContainer(tester).read(expiryAlertsProvider.notifier).sync();
      expect(os.scheduleCalls, calls);
      expect(os.permissionRequests, 1);
    });

    testWidgets('an edited date moves its reminders under the same ids', (
      tester,
    ) async {
      await open(tester);
      await settle(tester);
      final play = index(tester).all
          .firstWhere((i) => i.title == 'Play publisher');
      final ids = {
        alertId(play.id, ExpiryAlertKind.window),
        alertId(play.id, ExpiryAlertKind.expiryDay),
      };
      expect(os.pending.keys, containsAll(ids));

      await tester.runAsync(
        () => appContainer(tester)
            .read(vaultSessionProvider.notifier)
            .saveItem(
              play.copyWith(
                expiresAt: DateTime.utc(2026, 12, 24, 12),
                expiresSource: ExpirySource.user,
              ),
            ),
      );
      await settle(tester);
      final moved = [for (final id in ids) describe(os.pending[id]!)]..sort();
      expect(moved, [
        '“Play publisher” expires soon @ 2026-11-25T09:00',
        '“Play publisher” expires today @ 2026-12-24T09:00',
      ]);
      expect(os.pending, hasLength(6));
    });

    testWidgets('a deleted item’s reminders are cancelled and forgotten', (
      tester,
    ) async {
      await open(tester);
      await settle(tester);
      final profile = index(tester).all
          .firstWhere((i) => i.title == 'App Store profile');
      await tester.runAsync(
        () =>
            appContainer(tester)
                .read(vaultSessionProvider.notifier)
                .deleteItem(profile.id),
      );
      await settle(tester);
      expect(
        os.cancelled,
        containsAll([
          alertId(profile.id, ExpiryAlertKind.window),
          alertId(profile.id, ExpiryAlertKind.expiryDay),
        ]),
      );
      expect(os.pending, hasLength(4));
      expect(ledger(tester).scheduled.containsKey(profile.id), isFalse);
    });

    testWidgets('switching reminders off withdraws them; on brings them back', (
      tester,
    ) async {
      await open(tester);
      await settle(tester);
      final settings = appContainer(tester).read(settingsProvider.notifier);

      settings.setExpiryReminders(false);
      await settle(tester);
      expect(os.pending, isEmpty);
      expect(ledger(tester).scheduled, isEmpty);

      settings.setExpiryReminders(true);
      await settle(tester);
      expect(os.pending, hasLength(6));
    });

    testWidgets('the Settings switch turns them off', (tester) async {
      await open(tester);
      await settle(tester);
      appContainer(tester).read(vaultSessionProvider); // keep it open
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.text('Expiry reminders'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Expiry reminders'),
            matching: find.byType(BCListGroupItem),
          ),
          matching: find.byType(BCSwitch),
        ),
      );
      await settle(tester);
      expect(
        appContainer(tester).read(settingsProvider).expiryReminders,
        isFalse,
      );
      expect(os.pending, isEmpty);
    });

    testWidgets('a fired reminder is never scheduled again after a restart', (
      tester,
    ) async {
      await open(tester);
      await settle(tester);
      final container = appContainer(tester);
      final file = container.read(alertLedgerFileProvider);

      // Pretend a day passed: tomorrow's 09:00 window reminders fired.
      final stored = file.load();
      for (final kinds in stored.scheduled.values) {
        kinds.updateAll(
          (kind, at) =>
              kind == ExpiryAlertKind.window &&
                  at.isBefore(DateTime.utc(2026, 10, 9))
              ? DateTime.utc(2026, 10, 1)
              : at,
        );
      }
      file.save(stored);
      os.pending.clear();
      final calls = os.scheduleCalls;

      await container.read(expiryAlertsProvider.notifier).sync();
      final after = file.load();
      final play = index(tester).all
          .firstWhere((i) => i.title == 'Play publisher');
      expect(after.wasDelivered(play.id, ExpiryAlertKind.window), isTrue);
      // Only the day reminders were re-checked; no window one came back.
      expect(
        os.pending.values.where(
          (a) => a.kind == ExpiryAlertKind.window && a.itemId == play.id,
        ),
        isEmpty,
      );
      expect(os.scheduleCalls, calls); // the rest were still scheduled
    });
  });
}
