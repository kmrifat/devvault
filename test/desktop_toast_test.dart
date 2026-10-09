import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';
import 'toasts.dart';

/// `showDesktopToast`: every kit shows the message with its action, runs
/// the action once, and closes by itself.
void main() {
  /// A button that shows a toast with [action] when pressed.
  Widget trigger({
    String title = '“Upload keystore” moved to Kitchenly',
    VoidCallback? action,
    Duration duration = const Duration(seconds: 4),
  }) => Builder(
    builder: (context) => DesktopButton(
      label: 'Show',
      onPressed: () => showDesktopToast(
        context,
        title: title,
        message: 'Kitchenly › Android',
        kind: DesktopToastKind.success,
        actionLabel: action == null ? null : 'Undo',
        onAction: action,
        duration: duration,
      ),
    ),
  );

  /// Settles, letting Fluent's InfoBar run its fade, which waits on
  /// timers rather than frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  for (final kit in DesktopKit.values) {
    group(kit.name, () {
      testWidgets('shows the message, runs the action once and closes', (
        tester,
      ) async {
        var undone = 0;
        await pumpDesktop(tester, kit, trigger(action: () => undone++));
        await tester.tap(find.text('Show'));
        await settle(tester);
        expect(
          toastTexts(tester),
          containsAll([
            '“Upload keystore” moved to Kitchenly',
            'Kitchenly › Android',
            'Undo',
          ]),
        );

        await tester.tap(find.text('Undo'));
        await settle(tester);
        expect(undone, 1);
        expect(find.text('Undo'), findsNothing);
        // Fluent's InfoBar keeps its own close timer running.
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('closes by itself after its duration', (tester) async {
        await pumpDesktop(tester, kit, trigger());
        await tester.tap(find.text('Show'));
        await settle(tester);
        expect(toastTexts(tester), isNotEmpty);

        await tester.pump(const Duration(seconds: 5));
        await settle(tester);
        expect(find.textContaining('moved to Kitchenly'), findsNothing);
      });
    });
  }

  for (final kit in [DesktopKit.macos, DesktopKit.yaru]) {
    testWidgets('${kit.name}: a new toast replaces the one showing', (
      tester,
    ) async {
      var n = 0;
      await pumpDesktop(
        tester,
        kit,
        Builder(
          builder: (context) => DesktopButton(
            label: 'Show',
            onPressed: () => showDesktopToast(context, title: 'Toast ${++n}'),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(find.text('Toast 1'), findsNothing);
      expect(find.text('Toast 2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('macos: hovering keeps the banner open and shows its ×', (
    tester,
  ) async {
    await pumpDesktop(tester, DesktopKit.macos, trigger());
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(
      find.byIcon(DesktopSymbol.remove.of(DesktopKit.macos)),
      findsNothing,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.textContaining('moved to Kitchenly')),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(find.textContaining('moved to Kitchenly'), findsOneWidget);

    await tester.tap(find.byIcon(DesktopSymbol.remove.of(DesktopKit.macos)));
    await tester.pumpAndSettle();
    expect(find.textContaining('moved to Kitchenly'), findsNothing);
  });
}
