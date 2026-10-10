import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/notification_plan.dart';
import 'package:devvault/data/agent_clients.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/sync_setup.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/services/biometric_key_store.dart';
import 'package:devvault/services/credential_store.dart';
import 'package:devvault/services/notifications.dart';
import 'package:devvault/shared/desktop_ui.dart' show DesktopButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import 'test_overrides.dart';

/// Records what is cancelled.
class _Scheduler implements AlertScheduler {
  final cancelled = <int>[];

  @override
  tz.Location get location => tz.UTC;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(PlannedAlert alert) async {}

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

void main() {
  setUpAll(loadTestCrypto);

  late Directory dir;
  late String vaultId;
  late MemoryCredentialStore keys;
  late MemoryBiometricKeyStore biometrics;
  late _Scheduler scheduler;

  Directory vaults() => Directory('${dir.path}/vaults');

  /// A locked vault with everything a device keeps for it: storage
  /// settings ([synced]), storage keys, a key behind biometrics, a pending
  /// and a delivered reminder, and a paired agent.
  Future<void> open(
    WidgetTester tester,
    AppLayout layout, {
    bool synced = true,
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dir = (await tester.runAsync(() => testSupportDir(TestVault.locked)))!;
    vaultId = vaults()
        .listSync()
        .whereType<Directory>()
        .single
        .uri
        .pathSegments
        .lastWhere((s) => s.isNotEmpty);
    if (synced) {
      File('${vaults().path}/$vaultId.sync/storage.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          json.encode(
            const SyncSettings(
              bucket: 'team-vaults',
              prefix: 'devvault',
            ).toJson(),
          ),
        );
    }
    keys = MemoryCredentialStore()
      ..values[SyncSetupNotifier.credentialKey(vaultId)] = '{}';
    biometrics = MemoryBiometricKeyStore()
      ..keys[vaultId] = Uint8List.fromList([1, 2, 3]);
    scheduler = _Scheduler();
    AlertLedgerFile(dir).save(
      AlertLedger(
        delivered: {
          'old-item': {ExpiryAlertKind.window},
        },
        scheduled: {
          'old-item': {
            ExpiryAlertKind.expiryDay: testNow.add(const Duration(days: 3)),
          },
        },
      ),
    );
    await tester.runAsync(
      () => AgentClientsFile(dir).save([
        PairedClient(
          tokenHash: 'a' * 64,
          name: 'claude-code',
          pairedAt: testNow,
        ),
      ]),
    );
    await tester.pumpWidget(
      testApp(
        location: Routes.recover,
        supportDir: dir,
        layout: layout,
        overrides: [
          credentialStoreProvider.overrideWithValue(keys),
          biometricKeyStoreProvider.overrideWithValue(biometrics),
          alertSchedulerProvider.overrideWithValue(scheduler),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps [text], then alternates real time and frames until [until] shows
  /// up: erasing does real file I/O.
  Future<void> tapAndWait(
    WidgetTester tester,
    String text, {
    required Finder until,
  }) async {
    await tester.pump();
    await tester.runAsync(() => tester.tap(find.text(text)));
    for (var i = 0; i < 200 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
          .toString();

  void expectEverythingErased() {
    expect(
      vaults().existsSync() ? vaults().listSync() : const [],
      isEmpty,
      reason: 'the vault and its .sync folder are gone',
    );
    expect(keys.values, isEmpty, reason: 'storage keys');
    expect(biometrics.keys, isEmpty, reason: 'key behind biometrics');
    expect(scheduler.cancelled, [
      alertId('old-item', ExpiryAlertKind.expiryDay),
    ], reason: 'the pending reminder is withdrawn');
    final ledger = AlertLedgerFile(dir).load();
    expect(ledger.delivered, isEmpty);
    expect(ledger.scheduled, isEmpty);
    expect(AgentClientsFile(dir).load(), isEmpty, reason: 'paired agents');
  }

  group('desktop', () {
    testWidgets('recover offers start over; ERASE erases and goes to create', (
      tester,
    ) async {
      await open(tester, AppLayout.desktop);
      await tester.tap(find.text('Start over…'));
      await tester.pumpAndSettle();
      expect(location(tester), Routes.startOver);
      expect(find.text('Start over with a new vault'), findsOneWidget);
      expect(find.text('vault $vaultId'), findsOneWidget);
      expect(
        find.textContaining('team-vaults, under devvault/$vaultId/'),
        findsOneWidget,
      );

      DesktopButton erase() => tester.widget<DesktopButton>(
        find.widgetWithText(DesktopButton, 'Erase and Start Over'),
      );
      expect(erase().onPressed, isNull, reason: 'nothing typed yet');
      await tester.enterText(find.byType(EditableText), 'ERAS');
      await tester.pump();
      expect(erase().onPressed, isNull, reason: 'not the whole word');
      await tester.enterText(find.byType(EditableText), ' erase ');
      await tester.pump();
      expect(erase().onPressed, isNotNull, reason: 'any case, trimmed');

      await tapAndWait(
        tester,
        'Erase and Start Over',
        until: find.text('Create a master password'),
      );
      expect(location(tester), Routes.create);
      expect(appContainer(tester).read(vaultSessionProvider), isA<NoVault>());
      expectEverythingErased();
    });

    testWidgets('a vault that does not sync says this is its only copy', (
      tester,
    ) async {
      await open(tester, AppLayout.desktop, synced: false);
      await tester.tap(find.text('Start over…'));
      await tester.pumpAndSettle();
      expect(
        find.text("This vault doesn't sync, so this is its only copy."),
        findsOneWidget,
      );
    });

    testWidgets('Back returns to the recovery key, erasing nothing', (
      tester,
    ) async {
      await open(tester, AppLayout.desktop);
      await tester.tap(find.text('Start over…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(location(tester), Routes.recover);
      expect(Directory('${vaults().path}/$vaultId').existsSync(), isTrue);
      expect(keys.values, isNotEmpty);
    });
  });

  testWidgets('phone: the same erase, from the recovery screen', (
    tester,
  ) async {
    await open(tester, AppLayout.mobile);
    await tester.tap(find.text('Lost the recovery key too? Start over…'));
    await tester.pumpAndSettle();
    expect(location(tester), Routes.startOver);

    BCButton erase() => tester.widget<BCButton>(
      find.widgetWithText(BCButton, 'Erase and start over'),
    );
    expect(erase().isDisabled, isTrue);
    await tester.enterText(find.byType(EditableText), 'ERASE');
    await tester.pump();
    expect(erase().isDisabled, isFalse);

    await tapAndWait(
      tester,
      'Erase and start over',
      until: find.text('Create a master password'),
    );
    expect(location(tester), Routes.create);
    expectEverythingErased();
  });
}
