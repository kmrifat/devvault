import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/format.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/vault/item_detail_pane.dart';
import 'package:devvault/services/clipboard_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'clipboard_guard_test.dart' show FakeClipboard;
import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  late FakeClipboard clipboard;

  Finder inDetail(Finder finder) =>
      find.descendant(of: find.byType(ItemDetailPane), matching: finder);

  Future<void> select(WidgetTester tester, String title) async {
    final index =
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;
    final item = index.all.firstWhere((i) => i.title == title);
    GoRouter.of(tester.element(find.byType(ItemDetailPane)))
        .go(Routes.vault(item: item.id));
    await tester.pumpAndSettle();
  }

  /// Opens the vault, then selects the item titled [title] (the sample
  /// vault's ids are random, so it can't be a starting link).
  Future<void> open(WidgetTester tester, [String? title]) async {
    tester.view
      ..physicalSize = const Size(1440, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    clipboard = FakeClipboard();
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      vault: TestVault.sample,
      layout: AppLayout.desktop,
      overrides: [
        clipboardGuardProvider.overrideWithValue(
          ClipboardGuard(clipboard: clipboard),
        ),
      ],
    );
    if (title != null) await select(tester, title);
  }

  testWidgets('says when nothing or a missing item is selected', (
    tester,
  ) async {
    await open(tester);
    expect(inDetail(find.text('No item selected')), findsOneWidget);
    GoRouter.of(tester.element(find.byType(ItemDetailPane)))
        .go(Routes.vault(item: '00000000-0000-4000-8000-00000000dead'));
    await tester.pumpAndSettle();
    expect(inDetail(find.text('This item isn’t in the vault')), findsOneWidget);
  });

  testWidgets('shows the type, place, tags, expiry and provenance', (
    tester,
  ) async {
    await open(tester, 'Upload keystore');
    expect(inDetail(find.text('Upload keystore')), findsOneWidget);
    expect(inDetail(find.text('Android Keystore')), findsOneWidget);
    expect(
      inDetail(find.text('Kitchenly · Android · Production')),
      findsOneWidget,
    );
    expect(inDetail(find.text('#release')), findsOneWidget);
    expect(inDetail(find.text('#signing')), findsOneWidget);
    expect(
      inDetail(find.textContaining('Valid until Jan 14, 2051')),
      findsOneWidget,
    );
    expect(inDetail(find.textContaining('24 years left')), findsOneWidget);
    expect(inDetail(find.text('From file')), findsOneWidget);
    expect(
      inDetail(find.textContaining('Created Oct 7, 2026 on this device')),
      findsOneWidget,
    );
    expect(inDetail(find.text('End-to-end encrypted')), findsOneWidget);
  });

  testWidgets('expiring, expired and undated items say so', (tester) async {
    await open(tester, 'Play publisher');
    expect(inDetail(find.textContaining('Expires Oct 19, 2026')), findsOne);
    expect(inDetail(find.textContaining('12 days left')), findsOneWidget);

    await select(tester, 'Distribution certificate');
    expect(inDetail(find.textContaining('Expired Oct 4, 2026')), findsOne);
    expect(inDetail(find.textContaining('3 days ago')), findsOneWidget);

    await select(tester, 'Web OAuth client');
    expect(inDetail(find.text('No expiry date')), findsOneWidget);
    expect(
      inDetail(find.text('Nothing in the file says when it expires.')),
      findsOneWidget,
    );
  });

  testWidgets('lists fields by name with secrets masked', (tester) async {
    await open(tester, 'Upload keystore');
    for (final label in [
      'Alias',
      'Store password',
      'Key password',
      'SHA-1',
      'SHA-256',
    ]) {
      expect(inDetail(find.text(label)), findsOneWidget, reason: label);
    }
    expect(inDetail(find.text('upload')), findsOneWidget);
    expect(find.textContaining('kitchenly-store-pass'), findsNothing);
    expect(find.textContaining('kitchenly-key-pass'), findsNothing);
    expect(find.bySemanticsLabel('Store password, hidden'), findsOneWidget);
  });

  testWidgets('reveal shows one secret, and moving on hides it again', (
    tester,
  ) async {
    await open(tester, 'Upload keystore');
    await tester.tap(find.bySemanticsLabel('Reveal Store password'));
    await tester.pumpAndSettle();
    expect(find.text('kitchenly-store-pass'), findsOneWidget);
    expect(find.textContaining('kitchenly-key-pass'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Hide Store password'));
    await tester.pumpAndSettle();
    expect(find.text('kitchenly-store-pass'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Reveal Store password'));
    await tester.pumpAndSettle();
    await select(tester, 'Maps API key');
    await select(tester, 'Upload keystore');
    expect(find.text('kitchenly-store-pass'), findsNothing);
  });

  testWidgets('copying a secret goes through the guard and says Copied', (
    tester,
  ) async {
    await open(tester, 'Upload keystore');
    final guard = appContainer(tester).read(clipboardGuardProvider);

    await tester.tap(find.bySemanticsLabel('Copy Alias'));
    await tester.pump();
    expect(clipboard.text, 'upload');
    expect(guard.isHoldingSecret, isFalse);

    await tester.tap(find.bySemanticsLabel('Copy Store password'));
    await tester.pump();
    expect(clipboard.text, 'kitchenly-store-pass');
    expect(guard.isHoldingSecret, isTrue);
    // Copying doesn't reveal it on screen.
    expect(find.text('kitchenly-store-pass'), findsNothing);
    expect(inDetail(find.text('Copied')), findsNWidgets(2));

    await tester.pump(const Duration(seconds: 2));
    expect(inDetail(find.text('Copied')), findsNothing);
    await guard.clearNow();
  });

  testWidgets('shows the file with its size and hash', (tester) async {
    await open(tester, 'Upload keystore');
    final index =
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;
    final file = index.all
        .firstWhere((i) => i.title == 'Upload keystore')
        .attachments
        .single;
    expect(inDetail(find.text('kitchenly-upload.jks')), findsOneWidget);
    expect(
      inDetail(find.text('2.6 KB · sha256 ${Format.shortHash(file.sha256)}')),
      findsOneWidget,
    );
    expect(
      inDetail(find.textContaining('Upload key for Play App Signing')),
      findsOneWidget,
    );

    // Saving it is covered in export_test.dart.
    expect(inDetail(find.text('Save as…')), findsOneWidget);
  });

  testWidgets('items without a file have no Export button', (tester) async {
    await open(tester, 'Maps API key');
    expect(inDetail(find.text('Export')), findsNothing);
    await select(tester, 'Upload keystore');
    expect(inDetail(find.text('Export')), findsOneWidget);
  });

  group('Format', () {
    test('field names read as labels', () {
      expect(Format.fieldLabel('store_password'), 'Store password');
      expect(Format.fieldLabel('key_id'), 'Key ID');
      expect(Format.fieldLabel('sha256'), 'SHA-256');
      expect(Format.fieldLabel('client_email'), 'Client email');
      expect(Format.fieldLabel('oauth_client_id'), 'OAuth client ID');
      expect(Format.fieldLabel('Alias'), 'Alias');
    });

    test('sizes and hashes', () {
      expect(Format.bytes(1), '1 byte');
      expect(Format.bytes(512), '512 bytes');
      expect(Format.bytes(2662), '2.6 KB');
      expect(Format.bytes(3 * 1024 * 1024), '3.0 MB');
      expect(Format.shortHash('0123456789abcdef'), '0123456789abcdef');
      expect(
        Format.shortHash('3f9a0c7e00000000000000000000000000b81dc21e'),
        '3f9a0c7e…b81dc21e',
      );
    });
  });
}
