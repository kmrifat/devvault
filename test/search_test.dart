import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/search/quick_open.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      vault: TestVault.sample,
      layout: AppLayout.desktop,
    );
  }

  Future<void> shortcut(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(VaultListPane))).state.uri
          .toString();

  /// Result titles in quick-open, top to bottom, and which is highlighted.
  (List<String>, String?) results(WidgetTester tester) {
    final rows = tester
        .widgetList<Semantics>(
          find.descendant(
            of: find.byType(QuickOpen),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.button == true,
            ),
          ),
        )
        .toList();
    String title(Semantics s) => s.properties.label!.split(', ').first;
    return (
      [for (final s in rows) title(s)],
      [
        for (final s in rows)
          if (s.properties.selected == true) title(s),
      ].firstOrNull,
    );
  }

  Finder quickOpenInput() => find.descendant(
    of: find.byType(QuickOpen),
    matching: find.byType(EditableText),
  );

  testWidgets('⌘F and Ctrl+F focus the search field', (tester) async {
    await open(tester);
    EditableText field() =>
        tester.widget<EditableText>(find.byType(EditableText).first);
    expect(field().focusNode.hasFocus, isFalse);

    await shortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyF,
    );
    expect(field().focusNode.hasFocus, isTrue);

    field().focusNode.unfocus();
    await tester.pump();
    await shortcut(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyF,
    );
    expect(field().focusNode.hasFocus, isTrue);
  });

  testWidgets('⌘K lists recent items; typing finds, Enter opens', (
    tester,
  ) async {
    await open(tester);
    await shortcut(
      tester,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.keyK,
    );
    expect(find.byType(QuickOpen), findsOneWidget);
    expect(find.text('Recently changed'), findsOneWidget);
    expect(results(tester).$1, hasLength(QuickOpen.maxResults));

    await tester.enterText(quickOpenInput(), 'firebase');
    await tester.pump();
    expect(results(tester).$1, ['Firebase config', 'Firebase config']);
    expect(results(tester).$2, 'Firebase config');

    await tester.enterText(quickOpenInput(), 'kitchenly ios');
    await tester.pump();
    expect(results(tester).$1, [
      'APNs auth key',
      'App Store profile',
      'Distribution certificate',
    ]);
    expect(results(tester).$2, 'APNs auth key');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(results(tester).$2, 'App Store profile');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(results(tester).$2, 'Distribution certificate');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final cert = index(tester).all
        .firstWhere((i) => i.title == 'Distribution certificate');
    expect(find.byType(QuickOpen), findsNothing);
    expect(location(tester), Routes.vault(item: cert.id));
  });

  testWidgets('secrets and notes are never found', (tester) async {
    await open(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    for (final query in ['kitchenly-store-pass', 'sk_live', 'Google holds']) {
      await tester.enterText(quickOpenInput(), query);
      await tester.pump();
      expect(find.text('No matches'), findsOneWidget, reason: query);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(QuickOpen), findsNothing);
  });
}
