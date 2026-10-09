import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/sync_controller.dart';
import 'package:devvault/data/sync_setup.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/settings/desktop_settings.dart';
import 'package:devvault/features/settings/sync_settings_screen.dart';
import 'package:devvault/services/credential_store.dart';
import 'package:devvault/shared/desktop_ui.dart'
    show DesktopButton, DesktopFormRow, DesktopPopup;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

import 'test_overrides.dart';
import 'toasts.dart';

const _accountId = '0123456789abcdef0123456789abcdef';
const _accessKey = 'AKIA-TEST-ACCESS';
const _secretKey = 'very-secret-access-key-do-not-store';

void main() {
  setUpAll(loadTestCrypto);

  group('SyncSettings', () {
    test('R2 needs an account id; others a region or an endpoint', () {
      expect(const SyncSettings(bucket: 'b').validate().keys, ['accountId']);
      expect(
        const SyncSettings(bucket: 'b', accountId: _accountId).validate(),
        isEmpty,
      );
      expect(
        const SyncSettings(
          provider: StorageProvider.aws,
          bucket: 'b',
        ).validate().keys,
        ['region'],
      );
      expect(
        const SyncSettings(
          provider: StorageProvider.minio,
          bucket: 'b',
          endpoint: 'not a url',
        ).validate().keys,
        ['endpoint'],
      );
      expect(const SyncSettings(accountId: _accountId).validate().keys, [
        'bucket',
      ]);
    });

    test('builds the right S3 config per provider', () {
      final r2 = const SyncSettings(
        accountId: 'ABCDEF0123456789ABCDEF0123456789',
        bucket: 'vault',
      ).toConfig();
      expect(
        r2.url(key: 'k').toString(),
        'https://abcdef0123456789abcdef0123456789.r2.cloudflarestorage.com/vault/k',
      );
      expect(r2.region, 'auto');
      final aws = const SyncSettings(
        provider: StorageProvider.aws,
        region: 'eu-west-1',
        bucket: 'vault',
        pathStyle: false,
      ).toConfig();
      expect(
        aws.url(key: 'k').toString(),
        'https://vault.s3.eu-west-1.amazonaws.com/k',
      );
      final minio = const SyncSettings(
        provider: StorageProvider.minio,
        endpoint: 'http://10.0.0.2:9000',
        bucket: 'vault',
      ).toConfig();
      expect(minio.region, 'us-east-1');
      expect(minio.url(key: 'k').toString(), 'http://10.0.0.2:9000/vault/k');
    });

    test('the folder becomes a key prefix', () {
      expect(const SyncSettings().rootPrefix, '');
      expect(
        const SyncSettings(prefix: '/team/devvault/').rootPrefix,
        'team/devvault/',
      );
      expect(
        const SyncSettings(
          accountId: _accountId,
          bucket: 'b',
          prefix: 'has space',
        ).validate().keys,
        ['prefix'],
      );
    });
  });

  group('screen', () {
    late MemoryCredentialStore keychain;
    late List<String> probes;
    late Object? probeError;
    late StorageCapabilities probed;
    late MemoryBackend bucket;
    late _GcGate gc;

    Future<void> open(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1440, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      keychain = MemoryCredentialStore();
      probes = [];
      probeError = null;
      // MinIO-like: deletes ignore If-Match.
      probed = const StorageCapabilities(
        conditionalCreate: true,
        conditionalUpdate: true,
        conditionalDelete: false,
      );
      bucket = MemoryBackend();
      gc = _GcGate(bucket);
      await pumpUnlockedApp(
        tester,
        location: Routes.settingsSync,
        vault: TestVault.sample,
        layout: AppLayout.desktop,
        overrides: [
          credentialStoreProvider.overrideWithValue(keychain),
          storageProbeProvider.overrideWithValue((
            settings,
            credentials,
            prefix,
          ) async {
            probes.add(prefix);
            if (probeError case final e?) throw e;
            return probed;
          }),
          storageBackendProvider.overrideWith(
            (ref) => ref.watch(syncSetupProvider) == null ? null : gc,
          ),
        ],
      );
    }

    Vault vault(WidgetTester tester) =>
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;

    /// The field in the storage form's row labelled [label] (N07b).
    Finder input(String label) => find.descendant(
      of: find.ancestor(
        of: find.text('$label:'),
        matching: find.byType(DesktopFormRow),
      ),
      matching: find.byType(EditableText),
    );

    Finder secret() => input('Secret access key');

    Future<void> fill(WidgetTester tester) async {
      await tester.enterText(input('Account ID'), _accountId);
      await tester.enterText(input('Bucket'), 'my-devvault');
      await tester.enterText(input('Folder'), 'devvault');
      await tester.enterText(input('Access key ID'), _accessKey);
      await tester.enterText(secret(), _secretKey);
      await tester.pump();
    }

    /// A sync may start (the chip spins): give it real time and frames
    /// until nothing is running or scheduled, so it never outlives the
    /// test.
    Future<void> settleSync(WidgetTester tester) async {
      for (var i = 0; i < 500; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final running =
            appContainer(tester).read(syncControllerProvider) is SyncRunning;
        if (!running && !tester.binding.hasScheduledFrame) break;
      }
    }

    /// Taps [label] and runs until [done]. [whenDone] checks the screen
    /// before sync settles (a toast is gone by then).
    Future<void> tapAndRun(
      WidgetTester tester,
      String label,
      bool Function() done, {
      void Function()? whenDone,
    }) async {
      final target = find.text(label).last; // a dialog's button wins
      await tester.ensureVisible(target);
      await tester.tap(target);
      for (var i = 0; i < 500 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(done(), isTrue, reason: '$label never finished');
      await tester.pump();
      whenDone?.call();
      await settleSync(tester);
    }

    bool turnOnEnabled(WidgetTester tester) =>
        tester
            .widget<DesktopButton>(
              find.ancestor(
                of: find.text('Turn On Sync'),
                matching: find.byType(DesktopButton),
              ),
            )
            .onPressed !=
        null;

    testWidgets('R2 is preselected; saving needs a passing test', (
      tester,
    ) async {
      await open(tester);
      expect(
        tester
            .widget<DesktopPopup<StorageProvider>>(
              find.byType(DesktopPopup<StorageProvider>),
            )
            .value,
        StorageProvider.r2,
      );
      expect(find.text('Cloudflare R2'), findsOneWidget);
      expect(turnOnEnabled(tester), isFalse);

      await tester.tap(find.text('Test Connection'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the bucket name'), findsOneWidget);
      expect(probes, isEmpty);

      await fill(tester);
      await tapAndRun(tester, 'Test Connection', () => probes.isNotEmpty);
      expect(
        probes.single,
        'devvault/${vault(tester).vaultId}/.devvault-probe',
      );
      expect(find.text('Connected, with a limitation'), findsOneWidget);
      expect(
        find.textContaining('ignores conditions on deletes'),
        findsOneWidget,
      );
      expect(turnOnEnabled(tester), isTrue);

      // Changing anything means testing again.
      await tester.enterText(input('Bucket'), 'other-bucket');
      await tester.pump();
      expect(turnOnEnabled(tester), isFalse);
    });

    testWidgets('says what the storage enforces, and keeps saying it', (
      tester,
    ) async {
      const writes = 'doesn’t enforce conditional writes';
      const deletes = 'ignores conditions on deletes';
      await open(tester);
      await fill(tester);

      // Everything enforced: a plain success, no warning.
      probed = const StorageCapabilities(
        conditionalCreate: true,
        conditionalUpdate: true,
        conditionalDelete: true,
      );
      await tapAndRun(tester, 'Test Connection', () => probes.isNotEmpty);
      expect(
        find.text('Connected · conditional writes enforced'),
        findsOneWidget,
      );
      expect(find.textContaining(writes), findsNothing);
      expect(find.textContaining(deletes), findsNothing);

      // Nothing enforced: both warnings, before and after turning sync on.
      probed = const StorageCapabilities(
        conditionalCreate: false,
        conditionalUpdate: false,
        conditionalDelete: false,
      );
      await tapAndRun(tester, 'Test Connection', () => probes.length == 2);
      expect(find.text('Connected, with a limitation'), findsOneWidget);
      expect(find.textContaining(writes), findsOneWidget);
      expect(find.textContaining(deletes), findsOneWidget);

      await tapAndRun(
        tester,
        'Turn On Sync',
        () => appContainer(tester).read(syncSetupProvider) != null,
      );
      // The saved setup's card carries them from now on.
      final card = find
          .ancestor(
            of: find.textContaining('Syncing with Cloudflare R2'),
            matching: find.byType(DesktopSettingsBox),
          )
          .first;
      for (final warning in [writes, deletes]) {
        expect(
          find.descendant(of: card, matching: find.textContaining(warning)),
          findsOneWidget,
        );
      }
      await settleSync(tester);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a refused key says so', (tester) async {
      await open(tester);
      await fill(tester);
      probeError = const StorageAccessDenied('403');
      await tapAndRun(tester, 'Test Connection', () => probes.isNotEmpty);
      expect(find.text('Connection failed'), findsOneWidget);
      expect(find.textContaining('refused these keys'), findsOneWidget);
      expect(turnOnEnabled(tester), isFalse);
    });

    testWidgets('saving keeps keys in the keychain and nowhere else', (
      tester,
    ) async {
      await open(tester);
      await fill(tester);
      await tapAndRun(tester, 'Test Connection', () => probes.isNotEmpty);
      await tapAndRun(
        tester,
        'Turn On Sync',
        () => appContainer(tester).read(syncSetupProvider) != null,
        whenDone: () =>
            expectNoSecretInToasts(tester, [_secretKey, _accessKey]),
      );
      final id = vault(tester).vaultId;
      expect(keychain.values.keys, ['s3:$id']);
      expect(keychain.values['s3:$id'], contains(_secretKey));
      expect(find.textContaining('Syncing with Cloudflare R2'), findsOneWidget);

      // Let a sync run, then search every file this device wrote and every
      // object in the bucket for the keys (AC).
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && bucket.keys.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      final root = vault(tester).store.root;
      final files = [
        ...root.listSync(recursive: true),
        ...Directory('${root.path}.sync').listSync(recursive: true),
      ].whereType<File>();
      expect(files, isNotEmpty);
      for (final file in files) {
        final text = String.fromCharCodes(file.readAsBytesSync());
        expect(text, isNot(contains(_secretKey)), reason: file.path);
        expect(text, isNot(contains(_accessKey)), reason: file.path);
      }
      expect(bucket.keys, isNotEmpty);
      for (final key in bucket.keys) {
        final text = String.fromCharCodes(
          (await tester.runAsync(() => bucket.get(key)))!.bytes,
        );
        expect(text, isNot(contains(_secretKey)), reason: key);
      }
      await settleSync(tester);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('the setup comes back after unlocking again', (tester) async {
      await open(tester);
      await fill(tester);
      await tapAndRun(tester, 'Test Connection', () => probes.isNotEmpty);
      await tapAndRun(
        tester,
        'Turn On Sync',
        () => appContainer(tester).read(syncSetupProvider) != null,
      );
      final container = appContainer(tester);
      container.read(vaultSessionProvider.notifier).lock();
      await tester.pumpAndSettle();
      expect(container.read(syncSetupProvider), isNull);
      await tester.runAsync(
        () =>
            container.read(vaultSessionProvider.notifier).unlock(testPassword),
      );
      for (
        var i = 0;
        i < 100 && container.read(syncSetupProvider) == null;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      final setup = container.read(syncSetupProvider)!;
      expect(setup.settings.bucket, 'my-devvault');
      expect(setup.credentials.secretAccessKey, _secretKey);
      expect(setup.capabilities!.conditionalDelete, isFalse);
      await settleSync(tester);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('turning sync off forgets keys and settings', (tester) async {
      await open(tester);
      await fill(tester);
      await tapAndRun(tester, 'Test Connection', () => probes.isNotEmpty);
      await tapAndRun(
        tester,
        'Turn On Sync',
        () => appContainer(tester).read(syncSetupProvider) != null,
      );
      await tester.tap(find.text('Turn Off'));
      await tester.pumpAndSettle();
      await tapAndRun(
        tester,
        'Turn Off',
        () => appContainer(tester).read(syncSetupProvider) == null,
      );
      expect(keychain.values, isEmpty);
      expect(
        Directory('${vault(tester).store.root.path}.sync').existsSync(),
        isFalse,
      );
      expect(find.text('Turn On Sync'), findsOneWidget);
      await settleSync(tester);
      await tester.pump(const Duration(seconds: 10));
    });

    /// Gives sync's real I/O, and its timers, time until [done].
    Future<void> runUntil(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 500 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(done(), isTrue, reason: 'timed out');
    }

    /// Turns sync on without the form, and runs until [done].
    Future<void> turnOn(WidgetTester tester, bool Function() done) async {
      unawaited(
        appContainer(tester)
            .read(syncSetupProvider.notifier)
            .save(
              const SyncSettings(accountId: _accountId, bucket: 'my-devvault'),
              const AwsCredentials(
                accessKeyId: _accessKey,
                secretAccessKey: _secretKey,
              ),
              probed,
            ),
      );
      await runUntil(tester, done);
    }

    Directory syncFolder(WidgetTester tester) =>
        Directory('${vault(tester).store.root.path}.sync');

    testWidgets('turning sync off waits for a blob GC still running', (
      tester,
    ) async {
      await open(tester);
      final release = gc.hold();
      await turnOn(tester, () => gc.reached);

      // GC is held mid-run, before it saves the sync state.
      var off = false;
      unawaited(
        appContainer(tester)
            .read(syncSetupProvider.notifier)
            .turnOff()
            .whenComplete(() => off = true),
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(off, isFalse, reason: 'turned off under a running GC');
      expect(keychain.values, isNotEmpty);
      expect(syncFolder(tester).existsSync(), isTrue);

      release();
      await runUntil(tester, () => off);
      final controller = appContainer(tester)
          .read(syncControllerProvider.notifier);
      expect(controller.lastBlobGc, isNotNull); // it finished
      expect(keychain.values, isEmpty);
      expect(syncFolder(tester).existsSync(), isFalse);
      expect(appContainer(tester).read(syncControllerProvider), isA<SyncOff>());
      await settleSync(tester);
      expect(syncFolder(tester).existsSync(), isFalse);
    });

    testWidgets('a sync waiting its turn finds sync off and does nothing', (
      tester,
    ) async {
      await open(tester);
      await turnOn(
        tester,
        () => switch (appContainer(tester).read(syncControllerProvider)) {
          SyncIdle(lastSync: _?) => true,
          _ => false,
        },
      );
      final container = appContainer(tester);
      final session = container.read(vaultSessionProvider.notifier);
      final edit = Completer<void>();
      // An edit holds the lock; turning off and then a sync queue behind.
      unawaited(session.exclusive(() => edit.future));
      var off = false;
      unawaited(
        container
            .read(syncSetupProvider.notifier)
            .turnOff()
            .whenComplete(() => off = true),
      );
      final lists = bucket.log.length;
      var synced = false;
      unawaited(
        container
            .read(syncControllerProvider.notifier)
            .syncNow()
            .whenComplete(() => synced = true),
      );

      edit.complete();
      await runUntil(tester, () => synced || bucket.log.length > lists);
      expect(bucket.log, hasLength(lists), reason: 'synced after turning off');
      expect(off, isTrue);
      expect(syncFolder(tester).existsSync(), isFalse);
      expect(container.read(syncControllerProvider), isA<SyncOff>());
      await settleSync(tester);
    });

    test('AwsCredentials never prints the secret', () {
      expect(
        const AwsCredentials(
          accessKeyId: _accessKey,
          secretAccessKey: _secretKey,
        ).toString(),
        isNot(contains(_secretKey)),
      );
    });
  });

  testWidgets('the Sync tab is reachable from Settings', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: Routes.settings,
      layout: AppLayout.desktop,
    );
    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncSettingsScreen), findsOneWidget);
    expect(
      GoRouter.of(tester.element(find.byType(SyncSettingsScreen))).state.uri
          .toString(),
      Routes.settingsSync,
    );
  });
}

/// [inner], except that blob GC's listing (`<vault_id>/blobs/`) can be held
/// until the test releases it.
class _GcGate implements StorageBackend {
  _GcGate(this.inner);

  final StorageBackend inner;
  Completer<void>? _hold;

  /// Whether GC has reached the held listing.
  bool reached = false;

  /// Holds the next GC listing; call the result to let it go on.
  void Function() hold() {
    final hold = _hold = Completer<void>();
    return hold.complete;
  }

  @override
  Future<List<RemoteObject>> list(String prefix) async {
    if (prefix.endsWith('/${ObjectType.blob.folder}/')) {
      if (_hold case final hold?) {
        reached = true;
        await hold.future;
        _hold = null;
      }
    }
    return inner.list(prefix);
  }

  @override
  Future<RemoteBody?> get(String key) => inner.get(key);

  @override
  Future<String> put(
    String key,
    Uint8List bytes, {
    WriteCondition condition = const WriteCondition.always(),
  }) => inner.put(key, bytes, condition: condition);

  @override
  Future<void> delete(String key, {String? ifMatch}) =>
      inner.delete(key, ifMatch: ifMatch);
}
