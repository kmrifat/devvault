import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';

/// `DesktopContextMenu` (the sidebar rows' menus): every kit opens the
/// same menu on a right click and runs the picked command.
void main() {
  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      testWidgets('a right click opens the menu and runs the picked command', (
        tester,
      ) async {
        final picked = <String>[];
        await pumpDesktop(
          tester,
          kit,
          DesktopContextMenu(
            actions: [
              DesktopMenuAction('New item…', () => picked.add('new')),
              DesktopMenuAction(
                'Delete app…',
                () => picked.add('delete'),
                destructive: true,
              ),
            ],
            child: const SizedBox(width: 200, height: 24, child: Text('Row')),
          ),
        );
        expect(find.text('New item…'), findsNothing);

        // A primary click is the row's own.
        await tester.tap(find.text('Row'), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.text('New item…'), findsNothing);

        await tester.tap(
          find.text('Row'),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(find.text('New item…'), findsOneWidget);
        final delete = tester.renderObject<RenderParagraph>(
          find.text('Delete app…'),
        );
        expect(delete.text.style?.color, DesktopColors.light.danger);

        await tester.tap(find.text('New item…'));
        await tester.pumpAndSettle();
        expect(picked, ['new']);
        expect(find.text('New item…'), findsNothing);
      });

      testWidgets('its commands are semantics actions too', (tester) async {
        final picked = <String>[];
        final handle = tester.ensureSemantics();
        await pumpDesktop(
          tester,
          kit,
          DesktopContextMenu(
            actions: [DesktopMenuAction('New item…', () => picked.add('new'))],
            child: const SizedBox(width: 200, height: 24, child: Text('Row')),
          ),
        );
        final node = tester.getSemantics(find.text('Row'));
        final id = CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'New item…'),
        );
        node.owner!.performAction(node.id, SemanticsAction.customAction, id);
        await tester.pumpAndSettle();
        expect(picked, ['new']);
        handle.dispose();
      });

      testWidgets('opens from the keyboard through its state', (tester) async {
        final picked = <String>[];
        final menu = GlobalKey<DesktopContextMenuState>();
        await pumpDesktop(
          tester,
          kit,
          DesktopContextMenu(
            key: menu,
            actions: [DesktopMenuAction('New item…', () => picked.add('new'))],
            child: const SizedBox(width: 200, height: 24, child: Text('Row')),
          ),
        );
        menu.currentState!.open();
        await tester.pumpAndSettle();
        await tester.tap(find.text('New item…'));
        await tester.pumpAndSettle();
        expect(picked, ['new']);
      });

      testWidgets('without commands it is just its child', (tester) async {
        await pumpDesktop(
          tester,
          kit,
          const DesktopContextMenu(actions: [], child: Text('Row')),
        );
        await tester.tap(
          find.text('Row'),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(find.byType(GestureDetector), findsNothing);
      });
    });
  }
}
