import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Renders the app icon sources into `assets/icon/` (P4-08). Not a test:
/// it only runs when asked, then `dart run flutter_launcher_icons` makes
/// every platform's sizes from them.
///
/// ```sh
/// DEVVAULT_RENDER_ICON=1 flutter test test/tool/app_icon_test.dart
/// dart run flutter_launcher_icons
/// ```
///
/// The mark is the app's own: Lucide's vault glyph, the one on the unlock
/// screen and in the sidebar, in white on the brand blue.
void main() {
  final skip = Platform.environment['DEVVAULT_RENDER_ICON'] == null;

  // The brand accent (#0485F7) lit from the top left, deepening to the
  // light theme's AA shade (#035DB0).
  const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B9BFF), Color(0xFF0485F7), Color(0xFF035DB0)],
    stops: [0, 0.45, 1],
  );
  const glyph = Color(0xFFFFFFFF);
  const size = 1024.0;

  Future<void> render(
    WidgetTester tester,
    String file,
    Widget art, {
    bool opaque = false,
  }) async {
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

  Widget vault(double glyphSize) =>
      Icon(LucideIcons.vault, size: glyphSize, color: glyph);

  testWidgets('full-bleed: iOS, Windows, Android legacy', (tester) async {
    await render(
      tester,
      'app_icon.png',
      DecoratedBox(
        decoration: const BoxDecoration(gradient: gradient),
        child: Center(child: vault(size * 0.58)),
      ),
      opaque: true,
    );
  }, skip: skip);

  testWidgets('macOS: Apple’s 824 px tile with its 100 px margin', (
    tester,
  ) async {
    await render(
      tester,
      'app_icon_macos.png',
      Padding(
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
          child: Center(child: vault(824 * 0.58)),
        ),
      ),
    );
  }, skip: skip);

  testWidgets('Android adaptive foreground (safe zone: inner 66%)', (
    tester,
  ) async {
    await render(
      tester,
      'app_icon_foreground.png',
      Center(child: vault(size * 0.40)),
    );
  }, skip: skip);
}
