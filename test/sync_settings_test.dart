import 'dart:io';

import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/sync_controller.dart';
import 'package:devvault/data/sync_setup.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/settings/sync_settings_screen.dart';
import 'package:devvault/services/credential_store.dart';
import 'package:devvault/shared/widgets/password_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
            (ref) => ref.watch(syncSetupProvider) == null ? null : bucket,
          ),
        ],
      );
    }

    Vault vault(WidgetTester tester) =>
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;

    Finder input(String label) => find.descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byType(BCTextField),
      ),
      matching: find.byType(EditableText),
    );

    Finder secret() => find.descendant(
      of: find.byType(PasswordField),
      matching: find.byType(EditableText),
    );

    Future<void> fill(WidgetTester tester) async {
      await tester.enterText(input('Account ID'), _accountId);
      await tester.enterText(input('Bucket'), 'my-devvault');
      await tester.enterText(input('Folder (optional)'), 'devvault');
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

    bool turnOnEnabled(WidgetTester tester) => !tester
        .widget<BCButton>(
          find.ancestor(
            of: find.text('Turn on sync'),
            matching: find.byType(BCButton),
          ),
        )
        .isDisabled;

    testWidgets('R2 is preselected; saving needs a passing test', (
      tester,
    ) async {
      await open(tester);
      expect(
        tester
            .widget<BCRadioGroup<StorageProvider>>(
              find.byType(BCRadioGroup<StorageProvider>),
            )
            .value,
        StorageProvider.r2,
      );
      expect(turnOnEnabled(tester), isFalse);

      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the bucket name'), findsOneWidget);
      expect(probes, isEmpty);

      await fill(tester);
      await tapAndRun(tester, 'Test connection', () => probes.isNotEmpty);
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
      await tapAndRun(tester, 'Test connection', () => probes.isNotEmpty);
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
      await tapAndRun(tester, 'Test connection', () => probes.length == 2);
      expect(find.text('Connected, with a limitation'), findsOneWidget);
      expect(find.textContaining(writes), findsOneWidget);
      expect(find.textContaining(deletes), findsOneWidget);

      await tapAndRun(
        tester,
        'Turn on sync',
        () => appContainer(tester).read(syncSetupProvider) != null,
      );
      // The saved setup's card carries them from now on.
      final card = find
          .ancestor(
            of: find.textContaining('Syncing with Cloudflare R2'),
            matching: find.byType(BCCard),
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
      await tapAndRun(tester, 'Test connection', () => probes.isNotEmpty);
      expect(find.text('Connection failed'), findsOneWidget);
      expect(find.textContaining('refused these keys'), findsOneWidget);
      expect(turnOnEnabled(tester), isFalse);
    });

    testWidgets('saving keeps keys in the keychain and nowhere else', (
      tester,
    ) async {
      await open(tester);
      await fill(tester);
      await tapAndRun(tester, 'Test connection', () => probes.isNotEmpty);
      await tapAndRun(
        tester,
        'Turn on sync',
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
      await tapAndRun(tester, 'Test connection', () => probes.isNotEmpty);
      await tapAndRun(
        tester,
        'Turn on sync',
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
      await tapAndRun(tester, 'Test connection', () => probes.isNotEmpty);
      await tapAndRun(
        tester,
        'Turn on sync',
        () => appContainer(tester).read(syncSetupProvider) != null,
      );
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      await tapAndRun(
        tester,
        'Turn off',
        () => appContainer(tester).read(syncSetupProvider) == null,
      );
      expect(keychain.values, isEmpty);
      expect(
        Directory('${vault(tester).store.root.path}.sync').existsSync(),
        isFalse,
      );
      expect(find.text('Turn on sync'), findsOneWidget);
      await settleSync(tester);
      await tester.pump(const Duration(seconds: 10));
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

  testWidgets('the screen is reachable from Settings', (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: Routes.settings,
      layout: AppLayout.desktop,
    );
    await tester.tap(find.text('Sync storage'));
    await tester.pumpAndSettle();
    expect(find.byType(SyncSettingsScreen), findsOneWidget);
  });
}
