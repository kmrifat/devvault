import 'dart:io';

import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/pairing.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/sync_setup.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/create_vault/join_vault_screen.dart';
import 'package:devvault/features/pairing/pair_screen.dart';
import 'package:devvault/services/clipboard_guard.dart';
import 'package:devvault/services/credential_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

import 'clipboard_guard_test.dart' show FakeClipboard;
import 'test_overrides.dart';
import 'toasts.dart';

const _accountId = '0123456789abcdef0123456789abcdef';
const _password = 'the password used elsewhere';
const _settings = SyncSettings(
  provider: StorageProvider.r2,
  accountId: _accountId,
  bucket: 'my-devvault',
  prefix: 'devvault',
);
const _credentials = AwsCredentials(
  accessKeyId: 'AKIA-PAIR',
  secretAccessKey: 'pair-secret',
);

void main() {
  setUpAll(loadTestCrypto);

  late MemoryBackend bucket;
  late MemoryCredentialStore keychain;
  late FakeClipboard clipboard;
  late DateTime now;

  List<Override> sharedOverrides() => [
    credentialStoreProvider.overrideWithValue(keychain),
    storageBackendFactoryProvider.overrideWithValue((_, _) => bucket),
    storageProbeProvider.overrideWithValue(
      (_, _, _) async => StorageCapabilities.full,
    ),
    clipboardGuardProvider.overrideWithValue(
      ClipboardGuard(clipboard: clipboard),
    ),
    // The cheapest Argon2id the format accepts, so tests stay fast.
    pairingOpsLimitProvider.overrideWithValue(1),
    pairingMemLimitProvider.overrideWithValue(8 * 1024 * 1024),
  ];

  setUp(() {
    bucket = MemoryBackend();
    keychain = MemoryCredentialStore();
    clipboard = FakeClipboard();
    now = testNow;
  });

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'never finished');
  }

  GoRouter router(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first));

  group('Pair a device (the sending side)', () {
    Future<void> open(WidgetTester tester, {bool sync = true}) async {
      tester.view
        ..physicalSize = const Size(1440, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpUnlockedApp(
        tester,
        location: Routes.settings,
        layout: AppLayout.desktop,
        overrides: sharedOverrides(),
        clock: () => now,
      );
      if (sync) {
        await tester.runAsync(
          () =>
              appContainer(tester)
                  .read(syncSetupProvider.notifier)
                  .save(_settings, _credentials, StorageCapabilities.full),
        );
        await tester.pump();
      }
    }

    /// The code as shown, `ABCD-EFGH`, without the dash.
    String shownCode(WidgetTester tester) {
      final shown = RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$');
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere(shown.hasMatch);
      return text.replaceAll('-', '');
    }

    bool qrShown() => find.byType(QrImageView).evaluate().isNotEmpty;

    testWidgets('without sync there is nothing to hand over', (tester) async {
      await open(tester, sync: false);
      expect(find.text('Pair a device'), findsNothing); // not in Settings
      router(tester).push(Routes.pair);
      await tester.pumpAndSettle();
      expect(find.byType(PairScreen), findsOneWidget);
      expect(find.text('Set up sync first'), findsOneWidget);
    });

    testWidgets('shows a QR and code that open to exactly the sync setup', (
      tester,
    ) async {
      await open(tester);
      final vaultId = (appContainer(
        tester,
      ).read(vaultSessionProvider) as Unlocked).vault.vaultId;
      expect(find.text('R2 · my-devvault'), findsNothing);
      expect(find.text('Cloudflare R2 · my-devvault'), findsOneWidget);
      await tester.ensureVisible(find.text('Pair a device'));
      // Sync is on, so its status chip keeps animating: no pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Pair a device'));
      await tester.pump();
      await settle(tester, qrShown);
      final code = shownCode(tester);
      expect(code, hasLength(8));
      expect(find.text('Works for 10:00'), findsOneWidget);

      await tester.tap(find.text('Copy pairing text'));
      await tester.pump();
      await settle(tester, () => clipboard.text != null);
      final payload = clipboard.text!;
      expect(payload, startsWith(Pairing.prefix));
      expect(payload, isNot(contains('pair-secret')));
      expectNoSecretInToasts(tester, [
        payload,
        code,
        Pairing.display(code),
        'pair-secret',
      ]);

      final contents = await tester.runAsync(
        () => Pairing.open(
          crypto: testCrypto,
          text: payload,
          code: code,
          now: now,
        ),
      );
      expect(contents!.vaultId, vaultId);
      expect(contents.settings.toJson(), _settings.toJson());
      expect(contents.credentials.secretAccessKey, 'pair-secret');

      // Copied pairing text leaves the clipboard after 30 s.
      await tester.pump(const Duration(seconds: 30));
      expect(clipboard.text, '');
    });

    testWidgets('after ten minutes the code is spent; New code makes another', (
      tester,
    ) async {
      await open(tester);
      router(tester).push(Routes.pair);
      await tester.pump();
      await settle(tester, qrShown);
      final first = shownCode(tester);

      now = now.add(const Duration(minutes: 10, seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Expired. Make a new code.'), findsOneWidget);
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.byType(QrImageView),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        lessThan(0.5),
      );
      expect(find.text('Copy pairing text'), findsNothing);

      await tester.tap(find.text('New code'));
      await tester.pump();
      await settle(tester, qrShown);
      expect(shownCode(tester), isNot(first));
      expect(find.text('Works for 10:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('Join with a pairing code (the receiving side)', () {
    late String remoteVaultId;

    /// A vault created and synced on another device, under `devvault/`.
    Future<void> vaultElsewhere(WidgetTester tester) async {
      await tester.runAsync(() async {
        final dir = Directory.systemTemp.createTempSync('devvault_pair_');
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
        await vault.putItem(
          vault.newItem(type: ItemType.genericSecret, title: 'Stripe key'),
        );
        await SyncEngine(
          vault: vault,
          backend: bucket,
          rootPrefix: 'devvault/',
          now: () => testNow,
        ).sync();
        remoteVaultId = vault.vaultId;
      });
    }

    Future<String> payloadFor(
      WidgetTester tester,
      String code, {
      DateTime? at,
    }) async => (await tester.runAsync(
      () => Pairing.seal(
        crypto: testCrypto,
        vaultId: remoteVaultId,
        settings: _settings,
        credentials: _credentials,
        code: code,
        now: at ?? now,
        ops: 1,
        mem: 8 * 1024 * 1024,
      ),
    ))!;

    Future<void> openJoin(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1440, 2600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await vaultElsewhere(tester);
      final dir = (await tester.runAsync(testSupportDir))!;
      await tester.pumpWidget(
        testApp(
          location: Routes.joinVault,
          supportDir: dir,
          overrides: sharedOverrides(),
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(JoinVaultScreen), findsOneWidget);
    }

    Finder field(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    );

    Future<void> use(WidgetTester tester, String payload, String code) async {
      await tester.enterText(field('pairing-text'), payload);
      await tester.enterText(field('pairing-code'), code);
      await tester.pump();
      final button = find.text('Use pairing code');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
    }

    // Desktops paste the pairing text; phones scan it (below).
    final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

    testWidgets('fills the storage, finds the vault, joins with the password', (
      tester,
    ) async {
      await openJoin(tester);
      await use(tester, await payloadFor(tester, 'ABCDEFGH'), 'abcd-efgh');
      await settle(
        tester,
        () => find.text('Vaults in this bucket').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      // The pasted text and code are gone from the screen once used.
      expect(
        tester.widget<EditableText>(field('pairing-text')).controller.text,
        isEmpty,
      );
      // The paired vault is picked, so the password is asked straight away.
      final password = find.descendant(
        of: find.byKey(const ValueKey('join-password')),
        matching: find.byType(EditableText),
      );
      expect(password, findsOneWidget);
      await tester.enterText(password, _password);
      await tester.pump();
      final join = find.text('Join vault');
      await tester.ensureVisible(join);
      await tester.tap(join);
      await settle(
        tester,
        () => appContainer(tester).read(syncSetupProvider) != null,
      );
      final session =
          appContainer(tester).read(vaultSessionProvider) as Unlocked;
      expect(session.vault.vaultId, remoteVaultId);
      expect(session.index.all.single.title, 'Stripe key');
      final setup = appContainer(tester).read(syncSetupProvider)!;
      expect(setup.settings.toJson(), _settings.toJson());
      expect(setup.credentials.secretAccessKey, 'pair-secret');
      await tester.pump(const Duration(seconds: 10));
    }, variant: desktop);

    testWidgets('a wrong code or an expired payload says so', (tester) async {
      await openJoin(tester);
      final payload = await payloadFor(tester, 'ABCDEFGH');

      await use(tester, payload, 'ABCDEFGJ');
      await settle(
        tester,
        () => find.text('That code doesn’t match.').evaluate().isNotEmpty,
      );
      expect(find.text('Vaults in this bucket'), findsNothing);

      final old = await payloadFor(
        tester,
        'ABCDEFGH',
        at: now.subtract(const Duration(minutes: 30)),
      );
      await use(tester, old, 'ABCDEFGH');
      await settle(
        tester,
        () => find.text('This pairing code has expired.').evaluate().isNotEmpty,
      );

      await use(tester, 'not a code', 'ABCDEFGH');
      await settle(
        tester,
        () => find
            .text('This isn’t a DevVault pairing code.')
            .evaluate()
            .isNotEmpty,
      );
      expect(appContainer(tester).read(vaultSessionProvider), isA<NoVault>());
      expect(find.byType(BCSpinner), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    }, variant: desktop);

    testWidgets('phones scan the QR instead of pasting', (tester) async {
      await openJoin(tester);
      expect(find.text('Scan QR code'), findsOneWidget);
      expect(find.byKey(const ValueKey('pairing-text')), findsNothing);
      expect(find.byKey(const ValueKey('pairing-code')), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
