import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/item_editor/item_editor.dart';
import 'package:devvault/features/search/quick_open.dart';
import 'package:devvault/features/vault/desktop_inspector.dart';
import 'package:devvault/features/vault/desktop_item_type.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/shared/desktop_ui.dart';
import 'package:devvault/shared/widgets/type_icon_tile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'pump_desktop.dart';
import 'test_overrides.dart';

/// Desktop type tiles: each OS kit draws the type's symbol from its own
/// icon set, and no desktop screen falls back to bc_ui's `TypeIconTile`.
void main() {
  setUpAll(loadTestCrypto);

  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      testWidgets('draws the kit symbol for each type', (tester) async {
        await pumpDesktop(
          tester,
          kit,
          Wrap(
            children: [
              for (final type in ItemType.values) DesktopTypeTile(type: type),
            ],
          ),
        );
        for (final type in ItemType.values) {
          final symbol = (type as ItemType?).desktopSymbol;
          expect(
            find.byIcon(symbol.of(kit)),
            findsAtLeast(1),
            reason: '${type.label} on ${kit.name}',
          );
        }
        expect(find.byType(TypeIconTile), findsNothing);
      });

      testWidgets('an unknown type is a file; selected is on the accent', (
        tester,
      ) async {
        await pumpDesktop(
          tester,
          kit,
          const Row(
            children: [
              DesktopTypeTile(type: null, semanticLabel: 'x-new-type'),
              DesktopTypeTile(type: ItemType.sshKey, selected: true),
            ],
          ),
        );
        expect(find.byIcon(DesktopSymbol.typeFile.of(kit)), findsOneWidget);
        expect(find.bySemanticsLabel('x-new-type'), findsOneWidget);
        final onAccent = tester.widget<Icon>(
          find.byIcon(DesktopSymbol.typeSshKey.of(kit)),
        );
        expect(onAccent.color, DesktopColors.light.onAccent);
      });
    });
  }

  testWidgets('the inspector, editor sheet and quick open use desktop tiles', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      vault: TestVault.sample,
      layout: AppLayout.desktop,
    );
    final index =
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;
    final keystore = index.all.firstWhere((i) => i.title == 'Upload keystore');
    GoRouter.of(tester.element(find.byType(VaultListPane)))
        .go(Routes.vault(item: keystore.id));
    await tester.pumpAndSettle();

    Finder tileIn(Type screen) => find.descendant(
      of: find.byType(screen),
      matching: find.byType(DesktopTypeTile),
    );

    expect(tileIn(DesktopInspector), findsOneWidget);
    expect(find.byType(TypeIconTile), findsNothing);

    await tester.tap(find.bySemanticsLabel('Edit'));
    await tester.pumpAndSettle();
    expect(tileIn(ItemEditor), findsOneWidget);
    expect(find.byType(TypeIconTile), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(tileIn(QuickOpen), findsNWidgets(QuickOpen.maxResults));
    expect(find.byType(TypeIconTile), findsNothing);
  });
}
