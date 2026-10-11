import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:devvault/app/theme.dart';
import 'package:devvault/shared/widgets/app_mark.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the app icon sources into `assets/icon/`. Not a test: it only
/// runs when asked, then `tool/app_icon.sh` makes every platform's sizes
/// from them.
///
/// ```sh
/// tool/app_icon.sh
/// ```
///
/// The mark is the app's own ([AppMarkPainter], as on the unlock screen
/// and in the sidebar): a stack of credential files sealed by a lock,
/// white on rose. The 16 and 32 px macOS sizes use its simple mark.
void main() {
  final skip = Platform.environment['DEVVAULT_RENDER_ICON'] == null;

  const gradient = AppTheme.brandGradient;
  const size = 1024.0;

  Future<void> render(WidgetTester tester, String file, Widget art) async {
    tester.view
      ..physicalSize = const Size(size, size)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // flutter_test draws shadows as hard offsets unless told otherwise; the
    // flag is checked before tearDowns run, so it is restored below.
    debugDisableShadows = false;
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox.square(dimension: size, child: art),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    debugDisableShadows = true;
    File('assets/icon/$file').writeAsBytesSync(bytes!);
  }

  Widget mark({bool simple = false}) =>
      CustomPaint(painter: AppMarkPainter(simple: simple));

  Widget macosTile({bool simple = false}) => Padding(
    padding: const EdgeInsets.all(100),
    child: DecoratedBox(
      decoration: ShapeDecoration(
        gradient: gradient,
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(824 * 0.45),
        ),
        shadows: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: mark(simple: simple),
    ),
  );

  testWidgets('full-bleed: iOS, Windows, Android legacy', (tester) async {
    await render(
      tester,
      'app_icon.png',
      DecoratedBox(
        decoration: const BoxDecoration(gradient: gradient),
        child: mark(),
      ),
    );
  }, skip: skip);

  testWidgets('macOS: Apple’s 824 px tile with its 100 px margin', (
    tester,
  ) async {
    await render(tester, 'app_icon_macos.png', macosTile());
  }, skip: skip);

  testWidgets('macOS 16 and 32 px: the simple mark', (tester) async {
    await render(tester, 'app_icon_macos_small.png', macosTile(simple: true));
  }, skip: skip);

  testWidgets('Android adaptive foreground (safe zone: inner 66%)', (
    tester,
  ) async {
    // The adaptive background is the rose; the mark's cut-outs show it.
    await render(
      tester,
      'app_icon_foreground.png',
      Padding(padding: const EdgeInsets.all(size * 0.17), child: mark()),
    );
  }, skip: skip);
}
