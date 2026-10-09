import 'package:devvault/shared/desktop_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' as fl show InfoBar;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Material;
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
    expect(find.byIcon(DesktopSymbol.close.of(DesktopKit.macos)), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.textContaining('moved to Kitchenly')),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(find.textContaining('moved to Kitchenly'), findsOneWidget);

    await tester.tap(find.byIcon(DesktopSymbol.close.of(DesktopKit.macos)));
    await tester.pumpAndSettle();
    expect(find.textContaining('moved to Kitchenly'), findsNothing);
  });

  group('position (WALK-05)', () {
    const window = Size(1280, 800);

    /// The window's bottom edge less the status bar.
    const statusBarTop = 800 - DesktopMetrics.statusBarHeight;

    /// Shows a toast in a [window]-sized window and returns its rect.
    Future<Rect> shown(WidgetTester tester, DesktopKit kit) async {
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpDesktop(tester, kit, trigger(action: () {}));
      await tester.tap(find.text('Show'));
      await settle(tester);
      final toast = kit == DesktopKit.fluent
          ? find.byType(fl.InfoBar)
          : find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Toast');
      return tester.getRect(toast);
    }

    Future<void> closeAll(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
    }

    testWidgets('macos: the banner sits at the bottom right, above the '
        'status bar, clear of the toolbar and the inspector header', (
      tester,
    ) async {
      final rect = await shown(tester, DesktopKit.macos);
      expect(rect.right, window.width - DesktopMetrics.toastInset);
      expect(rect.bottom, statusBarTop - DesktopMetrics.toastInset);
      // The toolbar and the inspector's header row (title, Export, Edit,
      // ⋯) under it.
      const header = Rect.fromLTWH(
        0,
        0,
        1280,
        DesktopMetrics.toolbarHeight + 120,
      );
      expect(rect.overlaps(header), isFalse, reason: '$rect');
      await closeAll(tester);
    });

    testWidgets('yaru: the snackbar sits at the bottom centre, above the '
        'status bar', (tester) async {
      final rect = await shown(tester, DesktopKit.yaru);
      expect(rect.bottom, statusBarTop - DesktopMetrics.toastInset);
      final card = tester.getRect(
        find
            .ancestor(
              of: find.textContaining('moved to Kitchenly'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(card.center.dx, closeTo(window.width / 2, 0.5));
      expect(card.bottom, lessThanOrEqualTo(statusBarTop));
      await closeAll(tester);
    });

    testWidgets("fluent: the InfoBar doesn't cover the status bar", (
      tester,
    ) async {
      final rect = await shown(tester, DesktopKit.fluent);
      expect(rect.bottom, lessThanOrEqualTo(statusBarTop));
      expect(rect.center.dx, closeTo(window.width / 2, 0.5));
      await closeAll(tester);
    });
  });
}
