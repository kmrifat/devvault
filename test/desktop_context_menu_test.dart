import 'package:devvault/shared/desktop_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' as fl show Divider;
import 'package:flutter/material.dart' show Divider, MenuItemButton;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsAction;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';

/// `DesktopContextMenu` (the sidebar rows' menus): every kit opens the
/// same menu on a right click and runs the picked command, and the
/// keyboard works it as each OS's menus do.
void main() {
  /// The label of the command the keyboard is on: none when it's on the
  /// whole menu or outside it.
  String? highlighted() {
    final element = FocusManager.instance.primaryFocus?.context;
    if (element == null) return null;
    final texts = find
        .descendant(
          of: find.byElementPredicate((e) => e == element),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .toList();
    return texts.length == 1 ? texts.single : null;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

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

      group('from the keyboard', () {
        late List<String> picked;
        late FocusNode row;
        late GlobalKey<DesktopContextMenuState> menu;

        Future<void> pump(WidgetTester tester) async {
          picked = [];
          row = FocusNode(debugLabel: 'Row');
          addTearDown(row.dispose);
          menu = GlobalKey();
          await pumpDesktop(
            tester,
            kit,
            DesktopContextMenu(
              key: menu,
              actions: [
                DesktopMenuAction('New item…', () => picked.add('new')),
                // In groups: ↑/↓ step over the separators.
                DesktopMenuAction(
                  'Edit app…',
                  () => picked.add('edit'),
                  startsGroup: true,
                ),
                DesktopMenuAction(
                  'Delete app…',
                  () => picked.add('delete'),
                  startsGroup: true,
                ),
              ],
              child: Focus(
                focusNode: row,
                child: const SizedBox(
                  width: 200,
                  height: 24,
                  child: Text('Row'),
                ),
              ),
            ),
          );
          row.requestFocus();
          await tester.pump();
        }

        testWidgets('open() highlights the first command; ↓/↑ move and '
            'Return runs the highlighted one', (tester) async {
          await pump(tester);
          menu.currentState!.open();
          await tester.pumpAndSettle();
          expect(highlighted(), 'New item…');

          await press(tester, LogicalKeyboardKey.arrowDown);
          expect(highlighted(), 'Edit app…');
          await press(tester, LogicalKeyboardKey.arrowDown);
          expect(highlighted(), 'Delete app…');
          await press(tester, LogicalKeyboardKey.arrowUp);
          expect(highlighted(), 'Edit app…');

          await press(tester, LogicalKeyboardKey.enter);
          expect(picked, ['edit']);
          expect(find.text('Edit app…'), findsNothing);
          expect(row.hasPrimaryFocus, isTrue);
        });

        testWidgets('Escape closes it and the keyboard goes back to the row', (
          tester,
        ) async {
          await pump(tester);
          menu.currentState!.open();
          await tester.pumpAndSettle();
          expect(row.hasPrimaryFocus, isFalse);

          await press(tester, LogicalKeyboardKey.escape);
          expect(find.text('New item…'), findsNothing);
          expect(picked, isEmpty);
          expect(row.hasPrimaryFocus, isTrue);
        });

        testWidgets('after a right click, ↓ picks the first command and '
            'Escape closes it', (tester) async {
          await pump(tester);
          await tester.tap(
            find.text('Row'),
            buttons: kSecondaryMouseButton,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          // The menu has the keyboard, with nothing highlighted yet.
          expect(row.hasPrimaryFocus, isFalse);
          expect(highlighted(), isNull);

          await press(tester, LogicalKeyboardKey.arrowDown);
          expect(highlighted(), 'New item…');
          await press(tester, LogicalKeyboardKey.escape);
          expect(find.text('New item…'), findsNothing);
          expect(picked, isEmpty);
          expect(row.hasPrimaryFocus, isTrue);

          // ↑ picks the last; Space runs it.
          await tester.tap(
            find.text('Row'),
            buttons: kSecondaryMouseButton,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          await press(tester, LogicalKeyboardKey.arrowUp);
          expect(highlighted(), 'Delete app…');
          await press(tester, LogicalKeyboardKey.space);
          expect(picked, ['delete']);
          expect(find.text('Delete app…'), findsNothing);
        });
      });

      testWidgets('a separator goes above each group but the first', (
        tester,
      ) async {
        await pumpDesktop(
          tester,
          kit,
          DesktopContextMenu(
            actions: [
              // A first command that starts a group gets no separator.
              DesktopMenuAction('New item…', () {}, startsGroup: true),
              DesktopMenuAction('New app…', () {}),
              DesktopMenuAction('Edit app…', () {}, startsGroup: true),
              DesktopMenuAction(
                'Delete app…',
                () {},
                destructive: true,
                startsGroup: true,
              ),
            ],
            child: const SizedBox(width: 200, height: 24, child: Text('Row')),
          ),
        );
        await tester.tap(
          find.text('Row'),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final separators = find.byWidgetPredicate(
          (w) => w is Divider || w is fl.Divider,
        );
        expect(separators, findsNWidgets(2));
        double top(Finder f) => tester.getTopLeft(f).dy;
        final [first, second] = [
          for (final e in separators.evaluate())
            (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
        ]..sort();
        expect(first, greaterThan(top(find.text('New app…'))));
        expect(first, lessThan(top(find.text('Edit app…'))));
        expect(second, greaterThan(top(find.text('Edit app…'))));
        expect(second, lessThan(top(find.text('Delete app…'))));
      });

      if (kit == DesktopKit.macos) {
        testWidgets('its rows are the system menu\'s 24 pt', (tester) async {
          await pumpDesktop(
            tester,
            kit,
            DesktopContextMenu(
              actions: [DesktopMenuAction('New item…', () {})],
              child: const SizedBox(width: 200, height: 24, child: Text('Row')),
            ),
          );
          await tester.tap(
            find.text('Row'),
            buttons: kSecondaryMouseButton,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          final row = find.ancestor(
            of: find.text('New item…'),
            matching: find.byType(MenuItemButton),
          );
          expect(tester.getSize(row).height, DesktopMetrics.menuRowHeight);
        });
      }

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
