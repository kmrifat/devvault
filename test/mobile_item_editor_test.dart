import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/item_editor/item_editor_screen.dart';
import 'package:devvault/features/vault/item_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> open(WidgetTester tester, [String? location]) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 2000 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: location ?? Routes.vault(),
      vault: TestVault.sample,
      layout: AppLayout.mobile,
    );
  }

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri
          .toString();

  Finder labelled(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label,
  );

  Finder inForm(Finder f) =>
      find.descendant(of: find.byType(ItemEditorScreen), matching: f);

  /// Saving encrypts for real: lets it run until the page has gone.
  Future<void> settleSave(WidgetTester tester, Finder button) async {
    await tester.tap(button);
    for (
      var i = 0;
      i < 200 && find.byType(ItemEditorScreen).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('New item is a page of its own, not a dialog', (tester) async {
    await open(tester);
    await tester.tap(find.bySemanticsLabel('New item'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemEditorScreen), findsOneWidget);
    expect(find.byType(BCDialogContent), findsNothing);
    expect(
      location(tester),
      Routes.newItem(type: ItemType.genericSecret.wireName),
    );

    // Cancel goes back and saves nothing.
    final before = index(tester).all.length;
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemEditorScreen), findsNothing);
    expect(index(tester).all.length, before);
  });

  testWidgets('a new item with a secret field and tags', (tester) async {
    await open(tester);
    await tester.tap(find.bySemanticsLabel('New item'));
    await tester.pumpAndSettle();

    await tester.enterText(
      inForm(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText == 'e.g. Upload keystore',
        ),
      ),
      'Sentry token',
    );
    await tester.enterText(
      find.descendant(
        of: labelled('Value value'),
        matching: find.byType(EditableText),
      ),
      'sntrys_sample',
    );
    await tester.enterText(
      find.descendant(
        of: labelled('Add tag'),
        matching: find.byType(EditableText),
      ),
      'ci, release,',
    );
    await tester.pumpAndSettle();
    expect(inForm(find.text('#ci')), findsOneWidget);
    expect(inForm(find.text('#release')), findsOneWidget);
    // Typing it doesn't show it.
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: labelled('Value value'),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isTrue,
    );

    await settleSave(tester, inForm(find.text('Add item')));
    final saved = index(tester).all
        .firstWhere((i) => i.title == 'Sentry token');
    expect(saved.tags, ['ci', 'release']);
    expect(saved.fields.values.single.secret, isTrue);
    expect(saved.fields.values.single.value, 'sntrys_sample');
  });

  testWidgets('Edit opens the item’s page; the file’s fields are locked', (
    tester,
  ) async {
    final keystore = await () async {
      await open(tester);
      return index(tester).all.firstWhere((i) => i.title == 'Upload keystore');
    }();
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .push(Routes.item(keystore.id));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ItemScreen),
        matching: find.bySemanticsLabel('Edit'),
      ),
    );
    await tester.pumpAndSettle();
    expect(location(tester), Routes.editItem(keystore.id));
    expect(inForm(find.text('FROM THE FILE')), findsOneWidget);
    expect(inForm(find.text('upload')), findsOneWidget);
    // The file's values aren't text fields.
    expect(
      find.descendant(
        of: labelled('alias value'),
        matching: find.byType(EditableText),
      ),
      findsNothing,
    );

    await tester.enterText(
      inForm(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText == 'e.g. Upload keystore',
        ),
      ),
      'Upload keystore (2026)',
    );
    await settleSave(tester, inForm(find.text('Save')));
    final saved = index(tester).items[keystore.id]!;
    expect(saved.title, 'Upload keystore (2026)');
    expect(saved.fields['alias']!.value, 'upload');
    // Back on the item.
    expect(find.byType(ItemScreen), findsOneWidget);
  });
}
