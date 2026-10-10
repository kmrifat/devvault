import 'dart:io';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/app/theme.dart' show AppText;
import 'package:devvault/data/vault_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';
import 'toasts.dart';

void main() {
  setUpAll(loadTestCrypto);

  late Directory dir;
  late String recoveryKey;

  Future<void> openRecover(WidgetTester tester, AppLayout layout) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dir = (await tester.runAsync(() => testSupportDir(TestVault.locked)))!;
    recoveryKey = lastTestRecoveryKey!;
    await tester.pumpWidget(
      testApp(location: Routes.recover, supportDir: dir, layout: layout),
    );
    await tester.pumpAndSettle();
  }

  /// Does [action], then alternates real time and frames until [until]
  /// shows up. The work behind it does real file I/O and runs Argon2id on
  /// an isolate.
  Future<void> act(
    WidgetTester tester,
    Future<void> Function() action, {
    required Finder until,
  }) async {
    // Rebuild first: typing only marks the field dirty, and the button is
    // enabled by the next frame. Acting inside runAsync runs the handler
    // in the real zone, so its file I/O completes on its own.
    await tester.pump();
    await tester.runAsync(action);
    for (var i = 0; i < 200 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// Presses [button], then waits for [until] as [act] does.
  Future<void> press(
    WidgetTester tester,
    String button, {
    required Finder until,
  }) => act(tester, () => tester.tap(find.text(button)), until: until);

  /// Presses Return in the focused field, then waits for [until].
  Future<void> pressReturn(WidgetTester tester, {required Finder until}) => act(
    tester,
    () => tester.testTextInput.receiveAction(TextInputAction.done),
    until: until,
  );

  /// No text on screen (labels, messages, toasts) holds any part of [key].
  void expectKeyNotShown(WidgetTester tester, String key) {
    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      final plain = text.text.toPlainText();
      for (final group in key.split('-')) {
        expect(plain.contains(group), isFalse, reason: 'shows "$plain"');
      }
    }
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
          .toString();

  group('desktop key field', () {
    testWidgets('wraps the whole key over a few lines', (tester) async {
      await openRecover(tester, AppLayout.desktop);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.maxLines, 3);
      expect(field.minLines, 3);
      expect(field.style.fontFamily, AppText.monoFamily);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.textInputAction, TextInputAction.done);

      await tester.enterText(find.byType(EditableText), recoveryKey);
      await tester.pump();
      // Within the field's three lines, nothing scrolled out of sight. Two
      // or three: a line may only break at a dash before a letter (no break
      // between a hyphen and a digit), so it depends on the random key.
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final lines = {
        for (final box in editable.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: recoveryKey.length),
        ))
          box.top,
      };
      expect(lines.length, inInclusiveRange(2, 3));
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(EditableText),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.position.maxScrollExtent, 0);
    });

    testWidgets('a pasted key with line breaks recovers on Return', (
      tester,
    ) async {
      await openRecover(tester, AppLayout.desktop);
      // As copied from the recovery kit PDF: two rows of seven groups,
      // double spaces between groups, a line break between rows.
      final groups = recoveryKey.split('-');
      final pasted =
          '${groups.take(7).join('  ')}\n${groups.skip(7).join('  ')}\n';

      // A typo first: the message names no part of the key.
      final typo = pasted.replaceRange(0, 1, pasted[0] == 'A' ? 'B' : 'A');
      await tester.enterText(find.byType(EditableText), typo);
      final typoError = find.text(
        'This recovery key has a typo. Check each group.',
      );
      await pressReturn(tester, until: typoError);
      expect(typoError, findsOneWidget);
      expectKeyNotShown(tester, recoveryKey);
      expect(appContainer(tester).read(vaultSessionProvider), isA<Locked>());

      await tester.enterText(find.byType(EditableText), pasted);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        pasted,
        reason: 'the field keeps what was pasted, line breaks and all',
      );
      final stepTwo = find.text('Choose a new master password');
      await pressReturn(tester, until: stepTwo);
      expect(stepTwo, findsOneWidget);
      expect(appContainer(tester).read(vaultSessionProvider), isA<Unlocked>());
      expectKeyNotShown(tester, recoveryKey);
      for (final field in tester.widgetList<EditableText>(
        find.byType(EditableText),
      )) {
        expect(field.controller.text, isEmpty);
      }

      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'a brand new password');
      await tester.enterText(fields.at(1), 'a brand new password');
      await pressReturn(tester, until: find.text('New master password set'));
      expect(location(tester), Routes.vault());
      expectNoSecretInToasts(tester, [
        'a brand new password',
        recoveryKey,
        ...groups,
      ]);
    });
  });

  for (final layout in AppLayout.values) {
    group(layout.name, () {
      testWidgets('points at a typo before trying the key', (tester) async {
        await openRecover(tester, layout);
        final typo = recoveryKey.replaceRange(
          0,
          1,
          recoveryKey[0] == 'A' ? 'B' : 'A',
        );
        await tester.enterText(find.byType(EditableText), typo);
        final typoError = find.text(
          'This recovery key has a typo. Check each group.',
        );
        await press(tester, 'Continue', until: typoError);
        expect(typoError, findsOneWidget);

        await tester.enterText(find.byType(EditableText), 'K7QF-2M9X');
        final lengthError = find.text(
          'A recovery key has 14 groups of 4 characters',
        );
        await press(tester, 'Continue', until: lengthError);
        expect(lengthError, findsOneWidget);
        expect(appContainer(tester).read(vaultSessionProvider), isA<Locked>());
      });

      testWidgets("refuses another vault's key", (tester) async {
        await openRecover(tester, layout);
        final other = RecoveryKey.generate(testCrypto);
        await tester.enterText(
          find.byType(EditableText),
          other.toDisplayString(),
        );
        other.dispose();
        final wrongVault = find.text(
          "This recovery key doesn't belong to this vault",
        );
        await press(tester, 'Continue', until: wrongVault);
        expect(wrongVault, findsOneWidget);
      });

      testWidgets('recovery key, new password, vault open', (tester) async {
        await openRecover(tester, layout);
        // Typed sloppily: lower case, spaces instead of dashes.
        await tester.enterText(
          find.byType(EditableText),
          recoveryKey.toLowerCase().replaceAll('-', ' '),
        );
        final stepTwo = find.text('Choose a new master password');
        await press(tester, 'Continue', until: stepTwo);
        expect(stepTwo, findsOneWidget);
        expect(location(tester), Routes.recover, reason: 'held until reset');

        final fields = find.byType(EditableText);
        await tester.enterText(fields.at(0), 'a brand new password');
        await tester.enterText(fields.at(1), 'a brand new password');
        await press(
          tester,
          'Set password and open vault',
          until: find.text('New master password set'),
        );
        expect(location(tester), Routes.vault());
        expectNoSecretInToasts(tester, [
          'a brand new password',
          recoveryKey,
          ...recoveryKey.split('-'),
        ]);

        // The old password is gone, the new one works.
        final store = VaultStore(
          Directory('${dir.path}/vaults').listSync().first as Directory,
        );
        await tester.runAsync(() async {
          await expectLater(
            VaultKeys.unlockWithPassword(
              testCrypto,
              await store.readHeader(),
              testPassword,
            ),
            throwsA(isA<WrongPassword>()),
          );
          (await VaultKeys.unlockWithPassword(
            testCrypto,
            await store.readHeader(),
            'a brand new password',
          )).dispose();
        });
      });
    });
  }
}
