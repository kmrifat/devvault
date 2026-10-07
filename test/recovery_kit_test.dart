import 'dart:convert';
import 'dart:typed_data';

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/services/clipboard_guard.dart';
import 'package:devvault/services/file_saver.dart';
import 'package:devvault/services/recovery_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'clipboard_guard_test.dart' show FakeClipboard;
import 'test_overrides.dart';

class FakeFileSaver implements FileSaver {
  /// What was saved, as text (a PDF reads as Latin-1).
  final saved = <String, String>{};

  /// The buffers handed over, by reference: wiped after a PDF is saved.
  final buffers = <String, Uint8List>{};
  final mimeTypes = <String, String>{};

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    saved[fileName] = mimeType == 'application/pdf'
        ? latin1.decode(bytes)
        : utf8.decode(bytes);
    buffers[fileName] = bytes;
    mimeTypes[fileName] = mimeType;
    return true;
  }
}

class FakePrinter implements DocumentPrinter {
  String? printed;
  String? name;
  Uint8List? buffer;

  @override
  Future<bool> printPdf(Uint8List bytes, {required String name}) async {
    printed = latin1.decode(bytes);
    this.name = name;
    buffer = bytes;
    return true;
  }
}

void main() {
  setUpAll(loadTestCrypto);

  late FakeClipboard clipboard;
  late FakeFileSaver saver;
  late FakePrinter printer;
  late String keyText;

  /// Creates a vault the way D01 does and lands on the recovery kit.
  Future<void> openKit(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    clipboard = FakeClipboard();
    saver = FakeFileSaver();
    printer = FakePrinter();
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
          documentPrinterProvider.overrideWithValue(printer),
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
    await tester.tap(find.text('Save as text'));
    await tester.pumpAndSettle();
    final kit = saver.saved['DevVault Recovery Key.txt']!;
    expect(kit, contains(keyText));
    final vault =
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;
    expect(kit, contains(vault.vaultId));
    expect(kit, contains("Don't store it inside DevVault"));
  });

  /// PDF work (font loading, rendering) is real async work.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'never finished');
    await tester.pumpAndSettle();
  }

  bool isPdf(String? text) =>
      text != null &&
      text.startsWith('%PDF-') &&
      text.trimRight().endsWith('%%EOF');

  testWidgets('saves a one-page PDF, then wipes its bytes', (tester) async {
    await openKit(tester);
    await tester.tap(find.text('Save PDF'));
    await settle(
      tester,
      () => saver.saved.containsKey('DevVault Recovery Key.pdf'),
    );
    final pdf = saver.saved['DevVault Recovery Key.pdf'];
    expect(isPdf(pdf), isTrue);
    expect(saver.mimeTypes['DevVault Recovery Key.pdf'], 'application/pdf');
    // One page: the page tree counts a single page.
    expect(RegExp(r'/Type\s*/Pages\b').hasMatch(pdf!), isTrue);
    expect(RegExp(r'/Count\s*1\b').hasMatch(pdf), isTrue);
    expect(RegExp(r'/Count\s*([2-9]|\d\d)').hasMatch(pdf), isFalse);
    // Nothing kept: the buffer handed to the save dialog is zeroed after.
    expect(
      saver.buffers['DevVault Recovery Key.pdf']!.every((b) => b == 0),
      isTrue,
    );
    expect(find.text('Recovery kit saved as PDF'), findsOneWidget);
  });

  testWidgets('prints the PDF through the system dialog', (tester) async {
    await openKit(tester);
    await tester.tap(find.text('Print'));
    await settle(tester, () => printer.printed != null);
    expect(isPdf(printer.printed), isTrue);
    expect(printer.name, 'DevVault Recovery Key');
    expect(printer.buffer!.every((b) => b == 0), isTrue);
    expect(saver.saved, isEmpty);
  });
}
