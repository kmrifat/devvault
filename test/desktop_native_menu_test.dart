import 'package:devvault/shared/desktop_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show MenuItemButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_desktop.dart';

/// In the app's macOS window, context and pull-down menus are AppKit's
/// (P7-01): the app sends the commands over `devvault/menu` and runs the
/// one picked. Tests elsewhere cover the drawn menus.
void main() {
  late List<MethodCall> calls;

  /// What the fake AppKit answers: the index picked, or null.
  int? answer;

  setUp(() {
    calls = [];
    answer = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopNativeMenu.channel, (call) async {
          calls.add(call);
          return answer;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopNativeMenu.channel, null);
  });

  List<DesktopMenuAction> actions(List<String> picked) => [
    DesktopMenuAction(
      'New item…',
      macSymbol: 'doc.badge.plus',
      () => picked.add('new'),
    ),
    DesktopMenuAction('Edit app…', () => picked.add('edit')),
    DesktopMenuAction(
      'Delete app…',
      macSymbol: 'trash',
      () => picked.add('delete'),
      destructive: true,
      startsGroup: true,
    ),
  ];

  Future<void> rightClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(
      at,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a right click asks AppKit for the menu and runs the pick', (
    tester,
  ) async {
    final picked = <String>[];
    await pumpDesktop(
      tester,
      DesktopKit.macos,
      nativeWindow: true,
      DesktopContextMenu(
        actions: actions(picked),
        child: const SizedBox(width: 200, height: 24, child: Text('Row')),
      ),
    );

    answer = 2;
    final at = tester.getCenter(find.text('Row'));
    await rightClick(tester, at);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'popUp');
    final args = calls.single.arguments as Map;
    expect(args['x'], at.dx);
    expect(args['y'], at.dy);
    expect(args['items'], [
      {
        'title': 'New item…',
        'symbol': 'doc.badge.plus',
        'separatorBefore': false,
      },
      {'title': 'Edit app…', 'separatorBefore': false},
      {'title': 'Delete app…', 'symbol': 'trash', 'separatorBefore': true},
    ]);
    expect(picked, ['delete']);
    // Nothing is drawn: the menu is the system's.
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('dismissing the menu runs nothing', (tester) async {
    final picked = <String>[];
    await pumpDesktop(
      tester,
      DesktopKit.macos,
      nativeWindow: true,
      DesktopContextMenu(
        actions: actions(picked),
        child: const SizedBox(width: 200, height: 24, child: Text('Row')),
      ),
    );
    await rightClick(tester, tester.getCenter(find.text('Row')));
    expect(calls, hasLength(1));
    expect(picked, isEmpty);
  });

  testWidgets('opens from the keyboard under the row', (tester) async {
    final menu = GlobalKey<DesktopContextMenuState>();
    await pumpDesktop(
      tester,
      DesktopKit.macos,
      nativeWindow: true,
      DesktopContextMenu(
        key: menu,
        actions: actions([]),
        child: const SizedBox(width: 200, height: 24, child: Text('Row')),
      ),
    );
    menu.currentState!.open();
    await tester.pumpAndSettle();

    final row = tester.getRect(find.byKey(menu));
    final args = calls.single.arguments as Map;
    expect(args['x'], row.left + row.height / 2);
    expect(args['y'], row.bottom);
  });

  testWidgets('the pull-down drops the menu just below its button', (
    tester,
  ) async {
    final picked = <String>[];
    await pumpDesktop(
      tester,
      DesktopKit.macos,
      nativeWindow: true,
      DesktopPullDownButton(label: 'More', actions: actions(picked)),
    );
    answer = 0;
    await tester.tap(find.byType(DesktopPullDownButton));
    await tester.pumpAndSettle();

    final button = tester.getRect(find.byType(DesktopPullDownButton));
    final args = calls.single.arguments as Map;
    expect(args['x'], button.left);
    expect(args['y'], button.bottom + 4);
    expect(picked, ['new']);
  });

  testWidgets('without the app window, the drawn menu opens instead', (
    tester,
  ) async {
    await pumpDesktop(
      tester,
      DesktopKit.macos,
      DesktopContextMenu(
        actions: actions([]),
        child: const SizedBox(width: 200, height: 24, child: Text('Row')),
      ),
    );
    await rightClick(tester, tester.getCenter(find.text('Row')));
    expect(calls, isEmpty);
    expect(find.text('New item…'), findsOneWidget);
  });

  for (final kit in [DesktopKit.fluent, DesktopKit.yaru]) {
    testWidgets('${kit.name} keeps its own menu', (tester) async {
      await pumpDesktop(
        tester,
        kit,
        nativeWindow: true,
        DesktopContextMenu(
          actions: actions([]),
          child: const SizedBox(width: 200, height: 24, child: Text('Row')),
        ),
      );
      await rightClick(tester, tester.getCenter(find.text('Row')));
      expect(calls, isEmpty);
      expect(find.text('New item…'), findsOneWidget);
    });
  }
}
