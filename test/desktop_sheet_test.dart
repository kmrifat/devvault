import 'package:devvault/shared/desktop_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Scrollbar;
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart' as mac;
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';

/// Sheets and group boxes behave the same whichever kit draws them.
void main() {
  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      Future<Future<String?>> open(
        WidgetTester tester, {
        Widget child = const DesktopGroupBox(
          title: 'File',
          child: Text('AuthKey_TESTKEY123.p8'),
        ),
      }) async {
        late Future<String?> result;
        await pumpDesktop(
          tester,
          kit,
          Builder(
            builder: (context) => DesktopButton(
              label: 'Open',
              onPressed: () => result = showDesktopSheet<String>(
                context,
                builder: (context) => DesktopSheet(
                  title: 'Import',
                  icon: const SizedBox.square(
                    key: ValueKey('tile'),
                    dimension: 36,
                  ),
                  subtitle: const Text('Apple Auth Key · 241 bytes'),
                  actions: [
                    DesktopButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    DesktopButton(
                      label: 'Add to Vault',
                      kind: DesktopButtonKind.primary,
                      onPressed: () => Navigator.of(context).pop('added'),
                    ),
                  ],
                  child: child,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        return result;
      }

      testWidgets('shows its title, content and buttons', (tester) async {
        await open(tester);
        expect(find.text('Import'), findsOneWidget);
        expect(find.text('File'), findsOneWidget);
        expect(find.text('AuthKey_TESTKEY123.p8'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        // The tile and the line under the title.
        expect(find.byKey(const ValueKey('tile')), findsOneWidget);
        expect(find.text('Apple Auth Key · 241 bytes'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Apple Auth Key · 241 bytes')).dy,
          greaterThan(tester.getTopLeft(find.text('Import')).dy),
        );
      });

      testWidgets('the default action pops its result', (tester) async {
        final result = await open(tester);
        await tester.tap(find.text('Add to Vault'));
        await tester.pumpAndSettle();
        expect(await result, 'added');
        expect(find.text('Import'), findsNothing);
      });

      testWidgets('Escape closes it with nothing', (tester) async {
        final result = await open(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(await result, isNull);
        expect(find.text('Import'), findsNothing);
      });

      testWidgets('long content scrolls between the title and the buttons, '
          'and shows where it is cut', (tester) async {
        tester.view
          ..physicalSize = const Size(900, 500)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await open(
          tester,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 1; i <= 40; i++)
                SizedBox(height: 24, child: Text('Row $i')),
            ],
          ),
        );
        final window = Offset.zero & tester.view.physicalSize;
        final content = find.byType(DesktopScrollView);
        final area = tester.getRect(content);
        void fullyIn(Finder finder, Rect area) {
          final rect = tester.getRect(finder);
          expect(
            rect.top >= area.top - 0.5 && rect.bottom <= area.bottom + 0.5,
            isTrue,
            reason: '$rect is cut by $area',
          );
        }

        // The title and the buttons stay whole; the content takes the
        // height between them.
        fullyIn(find.text('Import'), window);
        expect(tester.getRect(find.text('Import')).bottom, lessThan(area.top));
        for (final label in ['Cancel', 'Add to Vault']) {
          fullyIn(find.text(label), window);
          expect(
            tester.getRect(find.text(label)).top,
            greaterThan(area.bottom),
          );
        }
        final position = tester
            .state<ScrollableState>(
              find.descendant(of: content, matching: find.byType(Scrollable)),
            )
            .position;
        expect(position.maxScrollExtent, greaterThan(0));

        // The scroll bar shows while there's more to see, not only while
        // scrolling.
        final bar = switch (kit) {
          DesktopKit.macos => find.byType(mac.MacosScrollbar),
          DesktopKit.fluent => find.byType(fl.Scrollbar),
          DesktopKit.yaru => find.byType(Scrollbar),
        };
        expect(
          find.descendant(of: find.byType(DesktopSheet), matching: bar),
          findsOneWidget,
        );
        final thumb = switch (kit) {
          DesktopKit.macos =>
            tester.widget<mac.MacosScrollbar>(bar).thumbVisibility,
          DesktopKit.fluent => tester.widget<fl.Scrollbar>(bar).thumbVisibility,
          DesktopKit.yaru => tester.widget<Scrollbar>(bar).thumbVisibility,
        };
        expect(thumb, isTrue);

        // A line marks each edge where rows are out of view.
        List<String> cues() => [
          for (final p in tester.widgetList<Positioned>(
            find.descendant(of: content, matching: find.byType(Positioned)),
          ))
            p.top == 0 ? 'top' : 'bottom',
        ];
        expect(cues(), ['bottom']);

        final mouse = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(mouse.hover(area.center));
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 300)));
        await tester.pumpAndSettle();
        expect(cues(), ['top', 'bottom']);

        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 5000)));
        await tester.pumpAndSettle();
        expect(cues(), ['top']);
        fullyIn(find.text('Row 40'), area);
        expect(find.text('Row 40').hitTestable(), findsOneWidget);
      });

      testWidgets('short content has no scroll cue', (tester) async {
        await open(tester);
        final content = find.byType(DesktopScrollView);
        expect(
          find.descendant(of: content, matching: find.byType(Positioned)),
          findsNothing,
        );
        final position = tester
            .state<ScrollableState>(
              find.descendant(of: content, matching: find.byType(Scrollable)),
            )
            .position;
        expect(position.maxScrollExtent, 0);
      });
    });
  }
}
