import 'dart:io';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/sync_controller.dart';
import 'package:devvault/data/sync_setup.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/sync/adopt_key_dialog.dart';
import 'package:devvault/features/sync/sync_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';
import 'toasts.dart';

void main() {
  setUpAll(loadTestCrypto);

  late MemoryBackend bucket;

  Future<void> open(
    WidgetTester tester, {
    StorageBackend? backend,
    bool phone = false,
  }) async {
    tester.view
      ..physicalSize = phone
          ? const Size(390 * 3, 844 * 3)
          : const Size(1440, 900)
      ..devicePixelRatio = phone ? 3 : 1;
    addTearDown(tester.view.reset);
    bucket = MemoryBackend();
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      vault: TestVault.sample,
      layout: phone ? AppLayout.mobile : AppLayout.desktop,
      overrides: [
        storageBackendProvider.overrideWithValue(backend ?? bucket),
        storageLabelProvider.overrideWithValue('R2'),
      ],
      // Not pumpAndSettle: the status chip animates while syncing. One
      // second is enough for the vault's page transition to finish.
      settle: () async {
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }

  SyncStatus status(WidgetTester tester) =>
      appContainer(tester).read(syncControllerProvider);

  /// Lets sync's real I/O run until [done] (at most ~10 s, for busy CI
  /// machines).
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'timed out; status ${status(tester)}');
  }

  bool synced(WidgetTester tester) => switch (status(tester)) {
    SyncIdle(lastSync: _?) => true,
    _ => false,
  };

  String vaultId(WidgetTester tester) => (appContainer(
    tester,
  ).read(vaultSessionProvider) as Unlocked).vault.vaultId;

  testWidgets('syncs on unlock and says so', (tester) async {
    await open(tester);
    await until(tester, () => synced(tester));
    expect(bucket.keys, contains('${vaultId(tester)}/vault.json'));
    // 12 items, 2 apps, 1 blob, vault.json.
    expect(bucket.keys, hasLength(16));
    expect(find.text('Synced · R2 · just now'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('blob GC runs after the first sync of the day', (tester) async {
    await open(tester);
    await until(tester, () => synced(tester));
    final controller = appContainer(tester)
        .read(syncControllerProvider.notifier);
    // The sample vault's one file is in use: nothing to collect.
    expect(controller.lastBlobGc, isNotNull);
    expect(controller.lastBlobGc!.collected, isEmpty);
    final preview = await tester.runAsync(controller.previewBlobGc);
    expect(preview!.dryRun, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('an edit syncs two seconds later', (tester) async {
    await open(tester);
    await until(tester, () => synced(tester));
    final notifier = appContainer(tester).read(vaultSessionProvider.notifier);
    late Item item;
    await tester.runAsync(() async {
      item = await notifier.saveItem(
        notifier.newItem(ItemType.genericSecret, 'Fresh token'),
      );
    });
    final key = '${vaultId(tester)}/items/${item.id}.enc';
    expect(bucket.keys, isNot(contains(key)));
    await tester.pump(const Duration(seconds: 1));
    expect(status(tester), isA<SyncIdle>()); // not yet
    await tester.pump(const Duration(seconds: 1));
    await until(tester, () => bucket.keys.contains(key) && synced(tester));
    await tester.pumpAndSettle();
  });

  testWidgets('⌘R syncs now', (tester) async {
    await open(tester);
    await until(tester, () => synced(tester));
    final lists = bucket.log.where((l) => l.startsWith('list')).length;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await until(
      tester,
      () =>
          bucket.log.where((l) => l.startsWith('list')).length > lists &&
          synced(tester),
    );
    await tester.pumpAndSettle();
  });

  int lists() => bucket.log.where((l) => l.startsWith('list')).length;

  testWidgets('coming back to the front syncs', (tester) async {
    await open(tester);
    await until(tester, () => synced(tester));
    final before = lists();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await until(tester, () => lists() > before && synced(tester));
    await tester.pumpAndSettle();
  });

  testWidgets('on a phone: the status shows and pulling down syncs', (
    tester,
  ) async {
    await open(tester, phone: true);
    await until(tester, () => synced(tester));
    expect(find.text('Synced · R2 · just now'), findsOneWidget);
    final before = lists();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await until(tester, () => lists() > before && synced(tester));
    await tester.pumpAndSettle();
  });

  testWidgets('offline keeps changes local and says so', (tester) async {
    final offline = MemoryBackend()
      ..failNext(StorageOp.list, const StorageUnavailable('no network'));
    await open(tester, backend: offline);
    await until(tester, () => status(tester) is SyncOffline);
    expect(find.text('Offline'), findsOneWidget);
    // Tapping retries; the network is back.
    await tester.tap(find.text('Offline'));
    await until(tester, () => synced(tester));
    await tester.pumpAndSettle();
  });

  testWidgets('wrong keys pause sync and point to settings', (tester) async {
    final denied = MemoryBackend()
      ..failNext(StorageOp.list, const StorageAccessDenied('403'));
    await open(tester, backend: denied);
    await until(tester, () => status(tester) is SyncFailed);
    expect(find.text('Sync paused'), findsOneWidget);
    await tester.tap(find.text('Sync paused'));
    await tester.pumpAndSettle();
    expect(
      GoRouter.of(tester.element(find.byType(SyncStatusChip))).state.uri
          .toString(),
      Routes.settingsSync,
    );
  });

  testWidgets('a key rotated on another device is adopted with the password', (
    tester,
  ) async {
    await open(tester);
    await until(tester, () => synced(tester));
    final id = vaultId(tester);

    // Another device: joins from the bucket, rotates the key, pushes.
    late String rotatedVkId;
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('other_device_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final root = Directory('${dir.path}/$id');
      for (final object in await bucket.list('$id/')) {
        final file = File(
          '${root.path}/${object.key.substring(id.length + 1)}',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes((await bucket.get(object.key))!.bytes);
      }
      final other = await Vault.unlock(
        crypto: testCrypto,
        store: VaultStore(root),
        password: testPassword,
        deviceId: '00000000-0000-4000-8000-0000000000ee',
        now: () => testNow,
      );
      await SyncEngine(vault: other, backend: bucket).sync();
      (await other.rotateVaultKey(testPassword)).dispose();
      await SyncEngine(vault: other, backend: bucket).sync();
      rotatedVkId = other.header.vkId;
    });

    await tester.runAsync(
      () =>
          appContainer(tester).read(syncControllerProvider.notifier).syncNow(),
    );
    await until(tester, () => status(tester) is SyncKeyChanged);
    await tester.pump();
    expect(find.text('Vault key changed'), findsOneWidget);

    await tester.tap(find.text('Vault key changed'));
    await tester.pumpAndSettle();
    expect(find.text('The vault key changed'), findsOneWidget);

    Future<void> submit(String password) async {
      await tester.enterText(
        find.descendant(
          of: find.byType(AdoptKeyForm),
          matching: find.byType(EditableText),
        ),
        password,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Use the new key'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      // Real I/O, then the dialog animates closed (which takes frame time),
      // and a sync may follow (its spinner never settles).
      for (
        var i = 0;
        i < 400 &&
            (find.text('Switching…').evaluate().isNotEmpty ||
                status(tester) is SyncRunning ||
                i == 0);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await submit('not my password');
    expect(find.textContaining("doesn't open the new key"), findsOneWidget);
    expect(status(tester), isA<SyncKeyChanged>());

    await submit(testPassword);
    expect(find.text('The vault key changed'), findsNothing);
    expectNoSecretInToasts(tester, [testPassword, 'not my password']);
    final session = appContainer(tester).read(vaultSessionProvider) as Unlocked;
    expect(session.vault.header.vkId, rotatedVkId);
    expect(session.index.items, hasLength(12));
    await until(tester, () => status(tester) is SyncIdle);
    await tester.pumpAndSettle();
  });

  testWidgets('without storage it says so and ⌘R does nothing', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      layout: AppLayout.desktop,
    );
    expect(status(tester), isA<SyncOff>());
    expect(find.text('Not syncing'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(status(tester), isA<SyncOff>());
  });

  test('"ago" reads naturally', () {
    final now = DateTime.utc(2026, 10, 7, 12);
    String ago(Duration d) => SyncStatusChip.ago(now.subtract(d), now);
    expect(ago(const Duration(seconds: 20)), 'just now');
    expect(ago(const Duration(minutes: 2)), '2 min ago');
    expect(ago(const Duration(hours: 3)), '3 h ago');
    expect(ago(const Duration(days: 1)), '1 day ago');
    expect(ago(const Duration(days: 4)), '4 days ago');
  });
}
