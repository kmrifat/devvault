import 'dart:convert';
import 'dart:typed_data';

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/services/clipboard_guard.dart';
import 'package:devvault/services/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'clipboard_guard_test.dart' show FakeClipboard;
import 'test_overrides.dart';

class FakeFileSaver implements FileSaver {
  final saved = <String, String>{};

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    saved[fileName] = utf8.decode(bytes);
    return true;
  }
}

void main() {
  setUpAll(loadTestCrypto);

  late FakeClipboard clipboard;
  late FakeFileSaver saver;
  late String keyText;

  /// Creates a vault the way D01 does and lands on the recovery kit.
  Future<void> openKit(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    clipboard = FakeClipboard();
    saver = FakeFileSaver();
    final dir = await tester.runAsync(testSupportDir);
    await tester.pumpWidget(
      testApp(
        location: Routes.create,
        supportDir: dir!,
        overrides: [
          clipboardGuardProvider.overrideWithValue(
            ClipboardGuard(clipboard: clipboard),
          ),
          fileSaverProvider.overrideWithValue(saver),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final c = appContainer(tester);
    await tester.runAsync(() async {
      final rk = await c
          .read(vaultSessionProvider.notifier)
          .create('a long master password');
      keyText = rk.toDisplayString();
      c.read(pendingRecoveryKeyProvider.notifier).hold(rk);
    });
    await tester.pumpAndSettle();
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
          .toString();

  testWidgets('shows the key as two rows of seven groups', (tester) async {
    await openKit(tester);
    final groups = keyText.split('-');
    expect(groups, hasLength(14));
    expect(find.text(groups.take(7).join('  ')), findsOneWidget);
    expect(find.text(groups.skip(7).join('  ')), findsOneWidget);
  });

  testWidgets('the vault stays closed until the user confirms', (tester) async {
    await openKit(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(location(tester), Routes.createRecoveryKit);

    await tester.tap(find.text("I've saved my recovery key"));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(location(tester), Routes.vault());
    expect(appContainer(tester).read(pendingRecoveryKeyProvider), isNull);
  });

  testWidgets('copy goes through the clipboard guard', (tester) async {
    await openKit(tester);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard.text, keyText);
    await tester.pump(const Duration(seconds: 30));
    expect(clipboard.text, '');
  });

  testWidgets('saves a text kit with the key and the vault id', (tester) async {
    await openKit(tester);
    await tester.tap(find.text('Save as text file'));
    await tester.pumpAndSettle();
    final kit = saver.saved['DevVault Recovery Key.txt']!;
    expect(kit, contains(keyText));
    final vault =
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;
    expect(kit, contains(vault.vaultId));
    expect(kit, contains("Don't store it inside DevVault"));
  });
}
