import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:bc_ui/bc_ui.dart' show BCSelect;
import 'package:devvault/features/item_editor/item_editor.dart';
import 'package:devvault/features/notes/notes.dart' show SecureNoteEditor;
import 'package:devvault/features/vault/desktop_inspector.dart';
import 'package:devvault/features/vault/item_detail_pane.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/services/clipboard_guard.dart';
import 'package:devvault/shared/widgets/markdown_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'clipboard_guard_test.dart' show FakeClipboard;
import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  late FakeClipboard clipboard;

  Future<void> open(WidgetTester tester, {AppLayout? layout}) async {
    tester.view
      ..physicalSize = layout == AppLayout.mobile
          ? const Size(430, 932)
          : const Size(1440, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    clipboard = FakeClipboard();
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      vault: TestVault.sample,
      layout: layout ?? AppLayout.desktop,
      overrides: [
        clipboardGuardProvider.overrideWithValue(
          ClipboardGuard(clipboard: clipboard),
        ),
      ],
    );
  }

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  GoRouter router(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first));

  Future<void> go(WidgetTester tester, String location) async {
    router(tester).go(location);
    await tester.pumpAndSettle();
  }

  Finder bodyField() => find.descendant(
    of: find.byType(SecureNoteEditor),
    matching: find.byType(EditableText),
  );

  Finder focusedField() =>
      find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus);

  /// Types [chars] where the caret is, one at a time, as a keyboard does.
  Future<void> type(WidgetTester tester, String chars) async {
    for (final ch in chars.split('')) {
      final value = tester
          .state<EditableTextState>(focusedField())
          .textEditingValue;
      final selection = value.selection;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: value.text.replaceRange(selection.start, selection.end, ch),
          selection: TextSelection.collapsed(offset: selection.start + 1),
        ),
      );
      await tester.pump();
      await tester.pump();
    }
  }

  /// Taps [button], then lets the real file I/O behind it finish.
  Future<void> settleWrite(
    WidgetTester tester,
    Finder button,
    bool Function() done,
  ) async {
    await tester.tap(button);
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'the write never finished');
    await tester.pumpAndSettle();
  }

  Future<void> newSecureNote(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Item noteTitled(WidgetTester tester, String title) =>
      index(tester).all.firstWhere((i) => i.title == title);

  group('desktop', () {
    testWidgets('Ctrl-Shift-N writes a note where the user is looking', (
      tester,
    ) async {
      await open(tester);
      final kitchenly = index(tester).apps.values
          .firstWhere((a) => a.name == 'Kitchenly');
      await go(tester, Routes.vault(app: kitchenly.id));

      await newSecureNote(tester);
      expect(find.text('New secure note'), findsOneWidget);
      // A note has no fields or expiry: its body takes their place.
      final editor = find.byType(ItemEditor);
      expect(
        find.descendant(of: editor, matching: find.text('Expires')),
        findsNothing,
      );
      expect(
        find.descendant(of: editor, matching: find.text('Add field')),
        findsNothing,
      );

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('item-name')),
          matching: find.byType(EditableText),
        ),
        'Release runbook',
      );
      await tester.tap(bodyField().first);
      await tester.pump();
      await type(tester, '# Steps\n- Bump **the** version\nTag it');
      await settleWrite(
        tester,
        find.text('Add note'),
        () => index(tester).all.any((i) => i.title == 'Release runbook'),
      );

      final note = noteTitled(tester, 'Release runbook');
      expect(note.typeName, ItemType.secureNote.wireName);
      expect(note.appId, kitchenly.id);
      expect(note.notes, '# Steps\n\n- Bump **the** version\n- Tag it');
      expect(note.fields, isEmpty);
      expect(note.attachments, isEmpty);
      expect(note.expiresAt, isNull);

      // The inspector shows the note rendered, first.
      final inspector = find.byType(DesktopInspector);
      expect(
        find.descendant(of: inspector, matching: find.byType(MarkdownNote)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: inspector, matching: find.text('Steps')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: inspector, matching: find.text('No expiry')),
        findsNothing,
      );

      // Copy goes through the clipboard guard, as a secret.
      await tester.tap(
        find.descendant(of: inspector, matching: find.text('Copy')),
      );
      await tester.pump();
      expect(clipboard.text, note.notes);
      expect(find.text('Note copied'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 31));
      expect(clipboard.text, isNot(note.notes));
    });

    testWidgets('editing a note: Markdown mode shows and edits the source', (
      tester,
    ) async {
      await open(tester);
      await newSecureNote(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('item-name')),
          matching: find.byType(EditableText),
        ),
        'Keys',
      );
      await tester.tap(bodyField().first);
      await tester.pump();
      await type(tester, '## Prod');
      await settleWrite(
        tester,
        find.text('Add note'),
        () => index(tester).all.any((i) => i.title == 'Keys'),
      );

      await tester.tap(
        find.descendant(
          of: find.byType(DesktopInspector),
          matching: find.text('Edit'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markdown'));
      await tester.pumpAndSettle();
      expect(find.text('## Prod'), findsOneWidget);
      await tester.enterText(bodyField(), '## Prod\n\n> rotate yearly');
      await tester.pump();
      await settleWrite(
        tester,
        find.text('Save'),
        () => noteTitled(tester, 'Keys').notes == '## Prod\n\n> rotate yearly',
      );
    });

    testWidgets('a new item switched to Secure Note takes its notes along', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('New item'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('item-notes')),
          matching: find.byType(EditableText),
        ),
        'Typed as notes',
      );
      await tester.tap(find.text('Generic Secret').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Secure Note').last);
      await tester.pumpAndSettle();
      expect(find.text('New secure note'), findsOneWidget);
      expect(bodyField(), findsOneWidget);
      expect(
        tester.widget<EditableText>(bodyField()).controller.text,
        contains('Typed as notes'),
      );
    });
  });

  group('organization notes', () {
    testWidgets('Edit organization… saves Markdown notes; the strip shows '
        'them', (tester) async {
      await open(tester);
      final kitchenly = index(tester).apps.values
          .firstWhere((a) => a.name == 'Kitchenly');
      await tester.runAsync(
        () =>
            appContainer(tester)
                .read(vaultSessionProvider.notifier)
                .saveApp(kitchenly.copyWith(organization: 'Acme Corp')),
      );
      await tester.pumpAndSettle();
      await go(tester, Routes.vault(org: 'Acme Corp'));
      expect(find.text('1 app'), findsOneWidget);

      await tester.tap(find.text('Edit organization…'));
      await tester.pumpAndSettle();
      expect(find.text('Edit “Acme Corp”'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('organization-notes')),
          matching: find.byType(EditableText),
        ),
        '**Billing** contact: finance@acme.example',
      );
      await settleWrite(
        tester,
        find.text('Save'),
        () =>
            organizationNotes(index(tester), 'Acme Corp') ==
            '**Billing** contact: finance@acme.example',
      );
      // Folded to its first line over the item table, rendered.
      expect(
        find.descendant(
          of: find.byType(VaultListPane),
          matching: find.text('Billing contact: finance@acme.example'),
        ),
        findsOneWidget,
      );
    });

    test(
      'notes of a name held by several records read and save as one',
      () async {
        final dir = await testSupportDir(TestVault.locked);
        final container = ProviderContainer(
          overrides: testOverrides(supportDir: dir),
        );
        addTearDown(container.dispose);
        final session = container.read(vaultSessionProvider.notifier);
        await session.unlock(testPassword);
        OrganizationRecord org(String notes) =>
            session.newOrganization('Globex', notes: notes);

        await session.saveOrganization(org('first'));
        await session.saveOrganization(org('second'));
        Unlocked unlocked() => container.read(vaultSessionProvider) as Unlocked;
        // Both records' notes, a blank line between.
        expect(
          organizationNotes(unlocked().index, 'Globex')!.split('\n\n').toSet(),
          {'first', 'second'},
        );

        await session.setOrganizationNotes('Globex', 'one note');
        expect(organizationNotes(unlocked().index, 'Globex'), 'one note');

        await session.setOrganizationNotes('Globex', '');
        expect(organizationNotes(unlocked().index, 'Globex'), isNull);

        // An organization with no record yet gets one.
        await session.setOrganizationNotes('Initech', 'TPS reports');
        expect(organizationNotes(unlocked().index, 'Initech'), 'TPS reports');
      },
    );
  });

  testWidgets('phone: a secure note is written and read on the item screen', (
    tester,
  ) async {
    await open(tester, layout: AppLayout.mobile);
    await tester.tap(find.bySemanticsLabel('New item'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BCSelect<ItemType>));
    await tester.pumpAndSettle();
    // The last type: the picker's list builds it once scrolled to.
    await tester.scrollUntilVisible(
      find.text('Secure Note'),
      100,
      scrollable: find
          .ancestor(
            of: find.text('Apple Auth Key').last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Secure Note').last);
    await tester.pumpAndSettle();
    expect(find.text('New secure note'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.hintText == 'e.g. Upload keystore',
      ),
      'Phone note',
    );
    await tester.tap(bodyField().first);
    await tester.pump();
    await type(tester, '# Wi-Fi\nguest network');
    await tester.ensureVisible(find.text('Add note'));
    await settleWrite(
      tester,
      find.text('Add note'),
      () => index(tester).all.any((i) => i.title == 'Phone note'),
    );
    final note = noteTitled(tester, 'Phone note');
    expect(note.notes, '# Wi-Fi\n\nguest network');

    await go(tester, Routes.item(note.id));
    expect(
      find.descendant(
        of: find.byType(ItemDetailPane),
        matching: find.text('Wi-Fi'),
      ),
      findsOneWidget,
    );
    expect(find.text('Copy'), findsOneWidget);
  });
}
