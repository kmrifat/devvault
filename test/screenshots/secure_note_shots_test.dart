@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/item_editor/item_draft.dart';
import 'package:devvault/features/notes/notes.dart' show SecureNoteEditor;
import 'package:devvault/features/vault/mobile_vault_screen.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../test_overrides.dart';
import 'harness.dart';

/// Secure notes (SPEC §6.5): one in the inspector and on the phone, the
/// note editor in Preview and Markdown, and an organization's notes over
/// its items.
void main() {
  setUpAll(loadAppFonts);

  const note =
      '# Release runbook\n'
      '\n'
      'Ship from `main` on **Tuesdays**; staging resets every night.\n'
      '\n'
      '## Steps\n'
      '\n'
      '1. Bump the version in `pubspec.yaml`.\n'
      '2. Tag it and push the tag.\n'
      '   - CI signs and uploads the builds.\n'
      '\n'
      '> Never paste the store keys into chat.\n'
      '\n'
      '```sh\n'
      'git tag -s v1.4.0 && git push origin v1.4.0\n'
      '```';

  const orgNote =
      '**Acme Corp**: client since 2024.\n'
      '\n'
      '- Billing: finance@acme.example\n'
      '- Escalation: the on-call channel';

  Unlocked session(WidgetTester tester) =>
      appContainer(tester).read(vaultSessionProvider) as Unlocked;

  AppRecord ledgerly(WidgetTester tester) =>
      session(tester).index.apps.values.firstWhere((a) => a.name == 'Ledgerly');

  /// A secure note in Ledgerly.
  Future<String> addNote(WidgetTester tester) async {
    final notifier = appContainer(tester).read(vaultSessionProvider.notifier);
    final draft =
        ItemDraft.create(ItemType.secureNote, appId: ledgerly(tester).id)
          ..title = 'Release runbook'
          ..notes = note;
    final saved = await tester.runAsync(
      () => notifier.saveItem(draft.toItem(notifier.newItem)),
    );
    await tester.pumpAndSettle();
    return saved!.id;
  }

  Future<void> selectNote(WidgetTester tester) async {
    await addNote(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(VaultSidebar),
        matching: find.text('Ledgerly'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(VaultListPane),
        matching: find.text('Release runbook'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> editNote(WidgetTester tester) async {
    await selectNote(tester);
    await tester.tap(find.bySemanticsLabel('Edit'));
    await tester.pumpAndSettle();
  }

  shot('N03-secure-note', Routes.vault(), sample: true, interact: selectNote);
  shot(
    'N03-secure-note-light',
    Routes.vault(),
    sample: true,
    interact: selectNote,
    brightness: Brightness.light,
  );
  // Preview, with the caret in the paragraph: its marks show, faintly.
  shot(
    'N03e-secure-note-editor',
    Routes.vault(),
    sample: true,
    interact: (tester) async {
      await editNote(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byType(SecureNoteEditor),
              matching: find.byType(EditableText),
            )
            .at(1),
      );
      await tester.pumpAndSettle();
    },
  );
  shot(
    'N03e-secure-note-markdown',
    Routes.vault(),
    sample: true,
    brightness: Brightness.light,
    interact: (tester) async {
      await editNote(tester);
      await tester.tap(find.text('Markdown'));
      await tester.pumpAndSettle();
    },
  );
  shot(
    'N03-organization-notes',
    Routes.vault(),
    sample: true,
    interact: (tester) async {
      final notifier = appContainer(tester).read(vaultSessionProvider.notifier);
      await tester.runAsync(() async {
        await notifier.saveApp(
          ledgerly(tester).copyWith(organization: 'Acme Corp'),
        );
        await notifier.setOrganizationNotes('Acme Corp', orgNote);
      });
      await tester.pumpAndSettle();
      GoRouter.of(tester.element(find.byType(VaultListPane)))
          .go(Routes.vault(org: 'Acme Corp'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Show notes'));
    },
  );
  shot(
    'B3-secure-note',
    Routes.vault(),
    device: ShotDevice.mobile,
    sample: true,
    interact: (tester) async {
      final id = await addNote(tester);
      GoRouter.of(tester.element(find.byType(MobileVaultScreen)))
          .push(Routes.item(id));
      await tester.pumpAndSettle();
    },
  );
}
