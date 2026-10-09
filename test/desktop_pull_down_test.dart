import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';

/// `DesktopPullDownButton` (the inspector's ⋯): every kit opens the same
/// menu and runs the picked command, from the pointer or the keyboard.
void main() {
  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      testWidgets('opens its menu and runs the picked command', (tester) async {
        final picked = <String>[];
        await pumpDesktop(
          tester,
          kit,
          DesktopPullDownButton(
            label: 'More actions',
            actions: [
              DesktopMenuAction('Replace file…', () => picked.add('replace')),
              DesktopMenuAction(
                'Delete item…',
                () => picked.add('delete'),
                destructive: true,
              ),
            ],
          ),
        );
        // Closed, it shows no commands, and screen readers can name it.
        expect(find.text('Delete item…'), findsNothing);
        expect(find.bySemanticsLabel('More actions'), findsOneWidget);

        await tester.tap(find.bySemanticsLabel('More actions'));
        await tester.pumpAndSettle();
        expect(find.text('Replace file…'), findsOneWidget);
        expect(find.text('Delete item…'), findsOneWidget);
        // The destructive command is in the danger colour.
        final delete = tester.renderObject<RenderParagraph>(
          find.text('Delete item…'),
        );
        expect(delete.text.style?.color, DesktopColors.light.danger);

        await tester.tap(find.text('Delete item…'));
        await tester.pumpAndSettle();
        expect(picked, ['delete']);
        expect(find.text('Delete item…'), findsNothing);

        await tester.tap(find.bySemanticsLabel('More actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Replace file…'));
        await tester.pumpAndSettle();
        expect(picked, ['delete', 'replace']);
      });

      testWidgets('the open menu takes the keyboard: ↓ and Return run a '
          'command, Escape closes it', (tester) async {
        final picked = <String>[];
        await pumpDesktop(
          tester,
          kit,
          DesktopPullDownButton(
            label: 'More actions',
            actions: [
              DesktopMenuAction('Replace file…', () => picked.add('replace')),
              DesktopMenuAction('Delete item…', () => picked.add('delete')),
            ],
          ),
        );
        Future<void> press(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        await tester.tap(find.bySemanticsLabel('More actions'));
        await tester.pumpAndSettle();
        await press(LogicalKeyboardKey.escape);
        expect(find.text('Replace file…'), findsNothing);
        expect(picked, isEmpty);

        await tester.tap(find.bySemanticsLabel('More actions'));
        await tester.pumpAndSettle();
        await press(LogicalKeyboardKey.arrowDown);
        await press(LogicalKeyboardKey.arrowDown);
        await press(LogicalKeyboardKey.enter);
        expect(picked, ['delete']);
        expect(find.text('Replace file…'), findsNothing);
      });
    });
  }
}
