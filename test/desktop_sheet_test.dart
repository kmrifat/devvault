import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';

/// Sheets and group boxes behave the same whichever kit draws them.
void main() {
  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      Future<Future<String?>> open(WidgetTester tester) async {
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
                  leading: const SizedBox.square(
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
                  child: const DesktopGroupBox(
                    title: 'File',
                    child: Text('AuthKey_TESTKEY123.p8'),
                  ),
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
    });
  }
}
