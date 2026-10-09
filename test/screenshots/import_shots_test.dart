@Tags(['golden'])
library;

import 'dart:io';

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/features/import/import_dialog.dart';
import 'package:devvault/features/import/import_draft.dart';
import 'package:devvault/features/import/paste_secret_sheet.dart';
import 'package:devvault/services/file_import.dart';
import 'package:devvault/shared/desktop_ui.dart'
    show DesktopTextField, DesktopTokenField;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// Always offers the same file, as if the user picked it.
class _PickOne implements FileOpener {
  const _PickOne(this.name);

  final String name;

  @override
  Future<List<PickedFile>> pick() async => [
    PickedFile(
      name: name,
      bytes: File('packages/cred_parsers/test/fixtures/$name')
          .readAsBytesSync(),
    ),
  ];
}

void main() {
  setUpAll(loadAppFonts);

  /// Opens the import dialog on [name] and waits for it to be read (the
  /// parse runs on an isolate, which needs real time).
  Future<void> importFile(WidgetTester tester) async {
    // Desktop has an Import button in the toolbar; phones an icon in the
    // header, then B4a's choice.
    var button = find.bySemanticsLabel(RegExp('^Import a file'));
    if (button.evaluate().isEmpty) {
      // Yaru's icon buttons are named by their tooltip instead.
      button = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').startsWith('Import a file'),
      );
    }
    if (button.evaluate().isNotEmpty) {
      await tester.tap(button.first);
    } else {
      await tester.tap(find.bySemanticsLabel('Import').first);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Pick a file'));
    }
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find.textContaining('Used for').evaluate().isNotEmpty) break;
    }
    expect(find.byType(ImportDialog), findsOneWidget);
  }

  final overrides = [
    fileOpenerProvider.overrideWithValue(
      const _PickOne('AuthKey_TESTKEY123.p8'),
    ),
  ];

  /// Fills the sheet in as the N04 frame shows it: a name, a typed
  /// platform and environment, and a tag. The Team ID is left for the
  /// user, so its "Required" note shows.
  Future<void> fillLikeTheFrame(WidgetTester tester) async {
    await importFile(tester);
    Finder input(Finder within) =>
        find.descendant(of: within, matching: find.byType(EditableText));
    await tester.enterText(
      input(find.byType(DesktopTextField)).first,
      'APNs key',
    );
    await tester.enterText(
      input(find.byKey(const ValueKey('import-platform'))),
      'ios',
    );
    await tester.enterText(
      input(find.byKey(const ValueKey('import-environment'))),
      'production',
    );
    await tester.enterText(input(find.byType(DesktopTokenField)), 'push');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // Nothing focused, as in the frame.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  shot(
    'N04-import',
    Routes.vault(),
    sample: true,
    overrides: overrides,
    interact: fillLikeTheFrame,
  );
  shot(
    'N04-import-light',
    Routes.vault(),
    sample: true,
    overrides: overrides,
    interact: fillLikeTheFrame,
    brightness: Brightness.light,
  );
  for (final kit in otherKits) {
    shot(
      'N04-import-${kit.name}-light',
      Routes.vault(),
      sample: true,
      overrides: overrides,
      interact: fillLikeTheFrame,
      brightness: Brightness.light,
      kit: kit,
    );
  }
  // WALK-04: a .p12's long Details box at the app's default window size.
  // The box scrolls on its own; the form, the Keep-password checkbox and
  // the expiry stay in view above the buttons.
  shot(
    'N04-import-p12-light',
    Routes.vault(),
    sample: true,
    window: const Size(1280, 800),
    overrides: [
      fileOpenerProvider.overrideWithValue(const _PickOne('legacy.p12')),
    ],
    interact: (tester) async {
      await tester.tap(find.bySemanticsLabel(RegExp('^Import a file')).first);
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 1000 && finder.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(finder, findsWidgets);
        // The sheet slides in.
        await tester.pump(const Duration(seconds: 1));
      }

      await waitFor(find.byKey(const ValueKey('import-secret-password')));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('import-secret-password')),
          matching: find.byType(EditableText),
        ),
        'test-password',
      );
      await tester.pump();
      await tester.tap(find.text('Unlock file'));
      await tester.pump();
      await waitFor(find.text('Details'));
      await tester.enterText(
        find
            .descendant(
              of: find.byType(DesktopTextField),
              matching: find.byType(EditableText),
            )
            .first,
        'Apple Development',
      );
      FocusManager.instance.primaryFocus?.unfocus();
    },
    brightness: Brightness.light,
  );
  shot(
    'B4-import',
    Routes.vault(),
    device: ShotDevice.mobile,
    sample: true,
    overrides: overrides,
    interact: importFile,
  );
  shot(
    'B4-import-end',
    Routes.vault(),
    device: ShotDevice.mobile,
    sample: true,
    overrides: overrides,
    interact: (tester) async {
      await importFile(tester);
      await tester.ensureVisible(
        find.descendant(
          of: find.byType(ImportDialog),
          matching: find.text('Add to vault'),
        ),
      );
    },
  );
  shot(
    'B4a-add',
    Routes.vault(),
    device: ShotDevice.mobile,
    sample: true,
    interact: (tester) async {
      await tester.tap(find.bySemanticsLabel('Import').first);
    },
  );
  shot(
    'B4b-paste-secret',
    Routes.vault(),
    device: ShotDevice.mobile,
    sample: true,
    interact: (tester) async {
      await tester.tap(find.bySemanticsLabel('Import').first);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Paste a secret'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.enterText(
        find
            .descendant(
              of: find.byType(PasteSecretSheet),
              matching: find.byType(EditableText),
            )
            .first,
        'Stripe secret key',
      );
    },
  );
}
