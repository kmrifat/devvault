import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/app_editor/app_draft.dart';
import 'package:devvault/features/app_editor/app_editor.dart';
import 'package:devvault/features/item_editor/item_draft.dart';
import 'package:devvault/features/item_editor/item_editor.dart';
import 'package:devvault/features/vault/desktop_inspector.dart';
import 'package:devvault/features/vault/item_screen.dart';
import 'package:devvault/features/vault/mobile_vault_screen.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:devvault/services/clipboard_guard.dart';
import 'package:devvault/shared/widgets/markdown_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'clipboard_guard_test.dart' show FakeClipboard;
import 'test_overrides.dart';
import 'toasts.dart';

/// Markdown notes on items and apps: the editors, where notes are shown,
/// and what a link in one does.
void main() {
  setUpAll(loadTestCrypto);

  const markdown =
      '## Rotation\n'
      '\n'
      'Rotate **every** 90 days with `make rotate`.\n'
      '\n'
      '- Runbook: [wiki](https://wiki.example/billing)\n'
      '- Logo: ![Acme logo](https://acme.example/logo.png)\n'
      '\n'
      '<b>raw html</b>';

  late FakeClipboard clipboard;

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  Finder editable(Finder within) =>
      find.descendant(of: within, matching: find.byType(EditableText));

  Future<void> open(WidgetTester tester, AppLayout layout) async {
    final desktop = layout == AppLayout.desktop;
    tester.view
      ..physicalSize = desktop
          ? const Size(1440, 1200)
          : const Size(390 * 3, 2400 * 3)
      ..devicePixelRatio = desktop ? 1 : 3;
    addTearDown(tester.view.reset);
    clipboard = FakeClipboard();
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      vault: TestVault.sample,
      layout: layout,
      overrides: [
        clipboardGuardProvider.overrideWithValue(
          ClipboardGuard(clipboard: clipboard),
        ),
      ],
    );
  }

  Future<void> settleWrite(
    WidgetTester tester,
    Finder button,
    bool Function() done,
  ) async {
    await tester.tap(button);
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'the write never finished');
    await tester.pumpAndSettle();
  }

  Future<Item> setItemNotes(WidgetTester tester, String title) async {
    final item = index(tester).all.firstWhere((i) => i.title == title);
    final saved = await tester.runAsync(
      () =>
          appContainer(tester)
              .read(vaultSessionProvider.notifier)
              .saveItem(item.copyWith(notes: markdown)),
    );
    await tester.pumpAndSettle();
    return saved!;
  }

  Future<AppRecord> setAppNotes(WidgetTester tester, String name) async {
    final app = index(tester).apps.values.firstWhere((a) => a.name == name);
    final saved = await tester.runAsync(
      () =>
          appContainer(tester)
              .read(vaultSessionProvider.notifier)
              .saveApp(app.copyWith(notes: markdown)),
    );
    await tester.pumpAndSettle();
    return saved!;
  }

  /// The note is drawn as Markdown: no Markdown syntax left in the text,
  /// the image in words, the HTML as text.
  void expectRendered(Finder within) {
    Finder text(String t) =>
        find.descendant(of: within, matching: find.text(t));
    expect(text('Rotation'), findsOneWidget);
    expect(text('Rotate every 90 days with make rotate.'), findsOneWidget);
    expect(text('Runbook: wiki'), findsOneWidget);
    expect(text('Logo: [Image: Acme logo]'), findsOneWidget);
    expect(text('<b>raw html</b>'), findsOneWidget);
    expect(
      find.descendant(of: within, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: within, matching: find.textContaining('## ')),
      findsNothing,
    );
  }

  /// Clicking the note's link copies its URL and says so; nothing opens.
  Future<void> expectLinkCopies(WidgetTester tester) async {
    await tester.tapOnText(find.textRange.ofSubstring('wiki'));
    await tester.pump();
    expect(clipboard.text, 'https://wiki.example/billing');
    expect(
      toastTexts(tester),
      containsAll(['Link copied', 'https://wiki.example/billing']),
    );
    await tester.pumpAndSettle(const Duration(seconds: 10));
  }

  group('drafts', () {
    AppRecord app() => AppRecord(
      id: '00000000-0000-4000-8000-000000000001',
      name: 'Billing API',
      createdAt: testNow,
      updatedAt: testNow,
      rev: Hlc.zero(testDeviceId),
      deviceId: testDeviceId,
    );

    test('an app draft edits notes; empty clears them', () {
      final created = AppDraft.create();
      expect(created.notes, '');
      final noted = (AppDraft.edit(
        app(),
      )..notes = '  $markdown\n').toApp((_) => app());
      expect(noted.notes, markdown);
      final draft = AppDraft.edit(noted);
      expect(draft.notes, markdown);
      expect((draft..notes = '  ').toApp((_) => app()).notes, isNull);
    });

    test('an item draft keeps a Markdown note exactly as typed', () {
      final base = Item(
        id: '00000000-0000-4000-8000-000000000002',
        typeName: ItemType.genericSecret.wireName,
        title: 'Stripe key',
        createdAt: testNow,
        updatedAt: testNow,
        rev: Hlc.zero(testDeviceId),
        deviceId: testDeviceId,
      );
      final item = (ItemDraft.edit(
        base,
      )..notes = markdown).toItem((_, _) => base);
      expect(item.notes, markdown);
      expect(ItemDraft.edit(item).notes, markdown);
    });
  });

  group('desktop', () {
    GoRouter router(WidgetTester tester) =>
        GoRouter.of(tester.element(find.byType(VaultListPane)));

    testWidgets('the inspector renders an item’s note; a link is copied', (
      tester,
    ) async {
      await open(tester, AppLayout.desktop);
      final item = await setItemNotes(tester, 'Upload keystore');
      router(tester).go(Routes.vault(item: item.id));
      await tester.pumpAndSettle();
      expectRendered(find.byType(DesktopInspector));
      await expectLinkCopies(tester);
    });

    testWidgets('the item editor: Markdown hint, Edit / Preview, saved as '
        'typed', (tester) async {
      await open(tester, AppLayout.desktop);
      final keystore = index(tester).all
          .firstWhere((i) => i.title == 'Upload keystore');
      router(tester).go(Routes.vault(item: keystore.id));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Markdown · not searchable'), findsOneWidget);
      await tester.enterText(
        editable(find.byKey(const ValueKey('item-notes'))),
        markdown,
      );
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('item-notes')), findsNothing);
      expectRendered(find.byType(ItemEditor));
      await tester.tap(find.text('Edit').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              editable(find.byKey(const ValueKey('item-notes'))),
            )
            .controller
            .text,
        markdown,
      );

      await settleWrite(
        tester,
        find.text('Save'),
        () => index(tester).items[keystore.id]!.notes == markdown,
      );
    });

    testWidgets('the app editor takes notes; the app strip folds them out', (
      tester,
    ) async {
      await open(tester, AppLayout.desktop);
      await tester.tap(
        find.descendant(
          of: find.byType(VaultSidebar),
          matching: find.text('Ledgerly'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit app…'));
      await tester.pumpAndSettle();

      expect(find.text('Markdown · not searchable'), findsOneWidget);
      await tester.enterText(
        editable(find.byKey(const ValueKey('app-notes'))),
        '\n$markdown\n\n',
      );
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expectRendered(find.byType(AppEditor));
      await settleWrite(
        tester,
        find.text('Save'),
        () =>
            index(tester).apps.values
                .firstWhere((a) => a.name == 'Ledgerly')
                .notes !=
            null,
      );
      final ledgerly = index(tester).apps.values
          .firstWhere((a) => a.name == 'Ledgerly');
      // Trimmed at both ends, otherwise as typed (SPEC §6.2).
      expect(ledgerly.notes, markdown);

      // Folded to their first line, then shown in full.
      final strip = find.byType(VaultListPane);
      expect(
        find.descendant(of: strip, matching: find.text('Rotation')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: strip, matching: find.byType(MarkdownNote)),
        findsNothing,
      );
      await tester.tap(find.bySemanticsLabel('Show notes'));
      await tester.pumpAndSettle();
      expectRendered(strip);
      await expectLinkCopies(tester);
      await tester.tap(find.bySemanticsLabel('Hide notes'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: strip, matching: find.byType(MarkdownNote)),
        findsNothing,
      );
    });

    testWidgets('an app without notes shows no notes', (tester) async {
      await open(tester, AppLayout.desktop);
      await tester.tap(
        find.descendant(
          of: find.byType(VaultSidebar),
          matching: find.text('Kitchenly'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit app…'), findsOneWidget);
      expect(find.bySemanticsLabel('Show notes'), findsNothing);
    });
  });

  group('phone', () {
    testWidgets('the item screen renders the note; a tap copies a link', (
      tester,
    ) async {
      await open(tester, AppLayout.mobile);
      await setItemNotes(tester, 'Upload keystore');
      await tester.tap(
        find.descendant(
          of: find.byType(MobileVaultScreen),
          matching: find.text('Upload keystore'),
        ),
      );
      await tester.pumpAndSettle();
      final notes = find.text('Rotation');
      await tester.ensureVisible(notes);
      await tester.pumpAndSettle();
      expectRendered(find.byType(ItemScreen));
      await expectLinkCopies(tester);
    });

    testWidgets('the app form takes notes, with a Markdown hint', (
      tester,
    ) async {
      await open(tester, AppLayout.mobile);
      final ledgerly = index(tester).apps.values
          .firstWhere((a) => a.name == 'Ledgerly');
      showAppEditor(
        tester.element(find.byType(MobileVaultScreen)),
        app: ledgerly,
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('app-notes'));
      await tester.ensureVisible(field);
      expect(find.textContaining('Markdown: **bold**'), findsOneWidget);
      await tester.enterText(editable(field), markdown);
      final save = find.text('Save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await settleWrite(
        tester,
        save,
        () => index(tester).apps[ledgerly.id]!.notes == markdown,
      );
    });

    testWidgets('choosing an app shows its notes over its items', (
      tester,
    ) async {
      await open(tester, AppLayout.mobile);
      final ledgerly = await setAppNotes(tester, 'Ledgerly');
      expect(find.text('App notes'), findsNothing);
      GoRouter.of(tester.element(find.byType(MobileVaultScreen)))
          .go(Routes.vault(app: ledgerly.id));
      await tester.pumpAndSettle();
      expect(find.text('App notes'), findsOneWidget);
      expectRendered(find.byType(MobileVaultScreen));
    });
  });
}
