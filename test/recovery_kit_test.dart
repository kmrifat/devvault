import 'dart:convert';
import 'dart:typed_data';

import 'package:devvault/app/layout.dart';
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
import 'toasts.dart';

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

  /// Creates a vault the way the create screen does and lands on the
  /// recovery kit.
  Future<void> openKit(WidgetTester tester, AppLayout layout) async {
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
        layout: layout,
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

  for (final layout in AppLayout.values) {
    final l = _Labels.of(layout);
    group(layout.name, () {
      testWidgets('shows the key as two rows of seven groups', (tester) async {
        await openKit(tester, layout);
        final groups = keyText.split('-');
        expect(groups, hasLength(14));
        expect(
          find.text(groups.take(7).join(l.groupSeparator)),
          findsOneWidget,
        );
        expect(
          find.text(groups.skip(7).join(l.groupSeparator)),
          findsOneWidget,
        );
      });

      testWidgets('the vault stays closed until the user confirms', (
        tester,
      ) async {
        await openKit(tester, layout);
        await tester.tap(find.text(l.confirm));
        await tester.pumpAndSettle();
        expect(location(tester), Routes.createRecoveryKit);

        await tester.tap(find.text(l.saved));
        await tester.pump();
        await tester.tap(find.text(l.confirm));
        await tester.pumpAndSettle();
        expect(location(tester), Routes.vault());
        expect(appContainer(tester).read(pendingRecoveryKeyProvider), isNull);
      });

      testWidgets('copy goes through the clipboard guard', (tester) async {
        await openKit(tester, layout);
        await tester.tap(find.text(l.copy));
        await tester.pumpAndSettle();
        expect(clipboard.text, keyText);
        // Not the key, nor any group of it.
        expectNoSecretInToasts(tester, [
          keyText,
          ...keyText.split(RegExp('[- ]')),
        ]);
        await tester.pump(const Duration(seconds: 30));
        expect(clipboard.text, '');
      });

      testWidgets('saves a text kit with the key and the vault id', (
        tester,
      ) async {
        await openKit(tester, layout);
        await tester.tap(find.text(l.saveText));
        await tester.pumpAndSettle();
        final kit = saver.saved['DevVault Recovery Key.txt']!;
        expect(kit, contains(keyText));
        expectNoSecretInToasts(tester, [
          keyText,
          ...keyText.split(RegExp('[- ]')),
        ]);
        final vault =
            (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;
        expect(kit, contains(vault.vaultId));
        expect(kit, contains("Don't store it inside DevVault"));
      });

      testWidgets('saves a one-page PDF, then wipes its bytes', (tester) async {
        await openKit(tester, layout);
        await tester.tap(find.text(l.savePdf));
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
        await openKit(tester, layout);
        await tester.tap(find.text(l.print));
        await settle(tester, () => printer.printed != null);
        expect(isPdf(printer.printed), isTrue);
        expect(printer.name, 'DevVault Recovery Key');
        expect(printer.buffer!.every((b) => b == 0), isTrue);
        expect(saver.saved, isEmpty);
      });
    });
  }
}

/// What the kit's controls say: the phone's (B) and desktop's (N02).
class _Labels {
  const _Labels({
    required this.groupSeparator,
    required this.saved,
    required this.confirm,
    required this.savePdf,
    required this.print,
    required this.saveText,
    required this.copy,
  });

  final String groupSeparator;
  final String saved;
  final String confirm;
  final String savePdf;
  final String print;
  final String saveText;
  final String copy;

  static _Labels of(AppLayout layout) => switch (layout) {
    AppLayout.mobile => const _Labels(
      groupSeparator: '  ',
      saved: "I've saved my recovery key",
      confirm: 'Continue',
      savePdf: 'Save PDF',
      print: 'Print',
      saveText: 'Save as text',
      copy: 'Copy',
    ),
    AppLayout.desktop => const _Labels(
      groupSeparator: '-',
      saved: "I've saved my recovery key somewhere safe",
      confirm: 'Open Vault',
      savePdf: 'Save PDF…',
      print: 'Print…',
      saveText: 'Save as Text…',
      copy: 'Copy',
    ),
  };
}
