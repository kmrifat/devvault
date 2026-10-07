import 'dart:io';

import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/app/session_redirect.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/sync_controller.dart';
import 'package:devvault/data/sync_setup.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/create_vault/join_vault_screen.dart';
import 'package:devvault/services/credential_store.dart';
import 'package:devvault/shared/widgets/password_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

const _accountId = '0123456789abcdef0123456789abcdef';
const _password = 'the password used elsewhere';

void main() {
  setUpAll(loadTestCrypto);

  late MemoryBackend bucket;
  late MemoryCredentialStore keychain;
  late String remoteVaultId;

  /// A vault created and synced on another device, under `devvault/`.
  Future<void> vaultElsewhere(WidgetTester tester) async {
    bucket = MemoryBackend();
    keychain = MemoryCredentialStore();
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('devvault_elsewhere_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final (vault, recovery) = await Vault.create(
        crypto: testCrypto,
        store: VaultStore(Directory('${dir.path}/v')),
        password: _password,
        deviceId: '00000000-0000-4000-8000-0000000000ee',
        now: () => testNow,
        opsLimit: KdfParams.minOpsLimit,
        memLimit: KdfParams.minMemLimit,
      );
      recovery.dispose();
      for (final title in ['Stripe key', 'APNs key']) {
        await vault.putItem(
          vault.newItem(type: ItemType.genericSecret, title: title),
        );
      }
      await SyncEngine(
        vault: vault,
        backend: bucket,
        rootPrefix: 'devvault/',
        now: () => testNow,
      ).sync();
      remoteVaultId = vault.vaultId;
    });
  }

  Future<Directory> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 2200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await vaultElsewhere(tester);
    final dir = (await tester.runAsync(testSupportDir))!;
    await tester.pumpWidget(
      testApp(
        location: Routes.create,
        supportDir: dir,
        overrides: [
          credentialStoreProvider.overrideWithValue(keychain),
          storageBackendFactoryProvider.overrideWithValue((_, _) => bucket),
          storageProbeProvider.overrideWithValue(
            (_, _, _) async => StorageCapabilities.full,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return dir;
  }

  Finder input(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(BCTextField)),
    matching: find.byType(EditableText),
  );

  Finder passwordInput(String label) => find.descendant(
    of: find.ancestor(
      of: find.text(label),
      matching: find.byType(PasswordField),
    ),
    matching: find.byType(EditableText),
  );

  Future<void> run(
    WidgetTester tester,
    String label,
    bool Function() done,
  ) async {
    final target = find.text(label).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    for (var i = 0; i < 500 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: '$label never finished');
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final running =
          appContainer(tester).read(syncControllerProvider) is SyncRunning;
      if (!running && !tester.binding.hasScheduledFrame) break;
    }
  }

  Future<void> fillStorage(WidgetTester tester) async {
    await tester.enterText(input('Account ID'), _accountId);
    await tester.enterText(input('Bucket'), 'my-devvault');
    await tester.enterText(input('Folder (optional)'), 'devvault');
    await tester.enterText(input('Access key ID'), 'AKIA-JOIN');
    await tester.enterText(passwordInput('Secret access key'), 'join-secret');
    await tester.pump();
  }

  testWidgets('joins a vault from the bucket and keeps syncing', (
    tester,
  ) async {
    final dir = await open(tester);
    await tester.tap(find.text('Join from your bucket'));
    await tester.pumpAndSettle();
    expect(find.byType(JoinVaultScreen), findsOneWidget);

    await fillStorage(tester);
    await run(
      tester,
      'Find vaults',
      () => find.text('Vaults in this bucket').evaluate().isNotEmpty,
    );
    expect(find.text('Vault ${remoteVaultId.substring(0, 8)}'), findsOneWidget);

    // A wrong password is caught before anything is downloaded.
    await tester.enterText(passwordInput('Master password'), 'not it at all');
    await run(
      tester,
      'Join vault',
      () => find
          .text("That password doesn't open this vault")
          .evaluate()
          .isNotEmpty,
    );
    expect(
      Directory('${dir.path}/vaults').existsSync() &&
          Directory('${dir.path}/vaults').listSync().isNotEmpty,
      isFalse,
    );
    expect(appContainer(tester).read(vaultSessionProvider), isA<NoVault>());

    final before = bucket.log.length;
    await tester.enterText(passwordInput('Master password'), _password);
    await run(
      tester,
      'Join vault',
      () => appContainer(tester).read(syncSetupProvider) != null,
    );
    final session = appContainer(tester).read(vaultSessionProvider) as Unlocked;
    expect(session.vault.vaultId, remoteVaultId);
    expect(session.index.all.map((i) => i.title), ['APNs key', 'Stripe key']);
    expect(keychain.values.keys, ['s3:$remoteVaultId']);
    expect(
      appContainer(tester).read(syncSetupProvider)?.settings.bucket,
      'my-devvault',
    );

    // The first sync after joining fetches nothing again: the download
    // recorded every object as synced.
    final afterJoin = bucket.log.sublist(before);
    final firstGet = afterJoin.indexWhere(
      (l) => l.startsWith('list devvault/$remoteVaultId/'),
    );
    final sync = afterJoin.sublist(
      afterJoin.lastIndexWhere(
            (l) => l.startsWith('list devvault/$remoteVaultId/'),
          ) +
          1,
    );
    expect(firstGet, isNonNegative);
    expect(
      sync.where((l) => l.startsWith('get') || l.startsWith('put')),
      isEmpty,
    );
    expect(find.text('Unlock your vault'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('an empty bucket says there is nothing to join', (tester) async {
    await open(tester);
    bucket = MemoryBackend(); // a different, empty bucket
    await tester.tap(find.text('Join from your bucket'));
    await tester.pumpAndSettle();
    await fillStorage(tester);
    await run(
      tester,
      'Find vaults',
      () => find.text('Vaults in this bucket').evaluate().isNotEmpty,
    );
    expect(find.text('No vault here yet'), findsOneWidget);
  });

  test('without a vault, both create and join are allowed', () {
    String? go(String path) => sessionRedirect(
      const NoVault(),
      Uri.parse(path),
      recoveryKitPending: false,
    );
    expect(go(Routes.create), isNull);
    expect(go(Routes.joinVault), isNull);
    expect(go(Routes.vault()), Routes.create);
  });
}
