import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/import/import_dialog.dart';
import 'package:devvault/features/import/paste_secret_sheet.dart';
import 'package:devvault/services/clipboard_guard.dart';
import 'package:devvault/shared/ui.dart' show BCButton, BCSelect, PasswordField;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import 'clipboard_guard_test.dart' show FakeClipboard;
import 'import_test.dart' show FakeFileOpener;
import 'test_overrides.dart';
import 'toasts.dart';

/// P3-03, B4a + B4b: on a phone, Import offers a file or a pasted secret.
void main() {
  setUpAll(loadTestCrypto);

  late FakeClipboard clipboard;

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    clipboard = FakeClipboard();
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      layout: AppLayout.mobile,
      overrides: [
        fileOpenerProvider.overrideWithValue(FakeFileOpener()),
        clipboardGuardProvider.overrideWithValue(
          ClipboardGuard(clipboard: clipboard),
        ),
      ],
    );
    await tester.tap(find.bySemanticsLabel('Import').first);
    await tester.pumpAndSettle();
  }

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  Finder inSheet(Finder f) =>
      find.descendant(of: find.byType(PasteSecretSheet), matching: f);

  /// The Name field: the sheet's first text field (the Secret is second).
  Finder nameInput() => inSheet(find.byType(EditableText)).first;

  testWidgets('Import offers a file or a secret (B4a)', (tester) async {
    await open(tester);
    expect(find.text('Add to vault'), findsOneWidget);
    expect(find.text('Pick a file'), findsOneWidget);
    expect(find.text('Paste a secret'), findsOneWidget);

    // Pick a file goes to the file picker and B4 (nothing picked here).
    await tester.tap(find.text('Pick a file'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a file'), findsNothing);
    expect(find.byType(ImportDialog), findsNothing);
  });

  testWidgets('a pasted secret becomes a Generic Secret, facts only (B4b)', (
    tester,
  ) async {
    const secret = 'sk_live_51HpasteD';
    await open(tester);
    await tester.tap(find.text('Paste a secret'));
    await tester.pumpAndSettle();
    expect(find.byType(PasteSecretSheet), findsOneWidget);

    // Nothing to save yet: both required fields say so.
    final add = inSheet(find.widgetWithText(BCButton, 'Add to vault'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('Give it a name'), findsOneWidget);
    expect(find.text('Paste or type the secret'), findsOneWidget);

    // Paste takes it off the clipboard; the field stays masked.
    clipboard.text = '$secret\n';
    await tester.ensureVisible(inSheet(find.text('Paste')));
    await tester.tap(inSheet(find.text('Paste')));
    await tester.pumpAndSettle();
    expect(clipboard.text, '');
    expect(find.text('Paste or type the secret'), findsNothing);
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(PasswordField),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.obscureText, isTrue);
    expect(field.controller.text, secret);

    await tester.enterText(nameInput(), 'Stripe secret key');
    final environment = inSheet(find.byType(BCSelect<String>)).last;
    await tester.ensureVisible(environment);
    await tester.pumpAndSettle();
    await tester.tap(environment);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(add);
      for (var i = 0; i < 200 && index(tester).all.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final item = index(tester).all.single;
    expect(item.typeName, ItemType.genericSecret.wireName);
    expect(item.title, 'Stripe secret key');
    expect(item.environment, 'production');
    final value = item.fields['value']!;
    expect(value.value, secret);
    expect(value.secret, isTrue);
    expect(value.source, FieldSource.user);
    // No date was given, so none is invented.
    expect(item.expiresAt, isNull);
    expect(item.expiresSource, isNull);

    expect(find.byType(PasteSecretSheet), findsNothing);
    expect(find.text('“Stripe secret key” added'), findsOneWidget);
    expectNoSecretInToasts(tester, [secret]);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}
