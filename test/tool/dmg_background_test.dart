import 'dart:io';
import 'dart:ui' as ui;

import 'package:devvault/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the background of the macOS disk image window into
/// `assets/dmg/`, at 1x and 2x. Not a test: it only runs when asked.
///
/// ```sh
/// DEVVAULT_RENDER_DMG=1 flutter test test/tool/dmg_background_test.dart
/// ```
///
/// The window (`tool/release/dmg_settings.py`) is [size] points, with
/// DevVault.app centred on [appCentre] and the Applications link on
/// [applicationsCentre]; Finder draws the icons and their names, this
/// draws the arrow between them and the line under it. Everything sits in
/// the top 330 points: Finder's path and status bars, when someone has them
/// on for every window, cover the bottom of the window whatever the
/// settings say.
void main() {
  final skip = Platform.environment['DEVVAULT_RENDER_DMG'] == null;

  const size = Size(660, 420);
  const appCentre = Offset(170, 150);
  const applicationsCentre = Offset(490, 150);

  for (final scale in [1.0, 2.0]) {
    testWidgets('background at ${scale.toInt()}x', (tester) async {
      tester.view
        ..physicalSize = size * scale
        ..devicePixelRatio = scale;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: SizedBox.fromSize(
              size: size,
              child: const _Background(
                appCentre: appCentre,
                applicationsCentre: applicationsCentre,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: scale);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      final name = scale == 1 ? 'background.png' : 'background@2x.png';
      File('assets/dmg/$name')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!);
    }, skip: skip);
  }
}

class _Background extends StatelessWidget {
  const _Background({
    required this.appCentre,
    required this.applicationsCentre,
  });

  final Offset appCentre;
  final Offset applicationsCentre;

  // Finder draws the icon names in the system's label colour, which is
  // dark on a light window; the background stays light in dark mode too.
  static const _paper = Color(0xFFFAFAFA);
  static const _wash = Color(0xFFFFF1F3);
  static const _text = Color(0xFF3F3F46);
  static const _secondary = Color(0xFF71717A);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_paper, _wash],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _Arrow(from: appCentre, to: applicationsCentre),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: 262,
            child: Column(
              spacing: 6,
              children: [
                Text(
                  'Drag DevVault to Applications to install it',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _text,
                  ),
                ),
                Text(
                  'Then open it from Launchpad or Spotlight.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: _secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A rose arrow arcing from the app's icon to the Applications link,
/// clear of both 128 pt icons.
class _Arrow extends CustomPainter {
  const _Arrow({required this.from, required this.to});

  final Offset from;
  final Offset to;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 88.0;
    final start = from + const Offset(gap, 0);
    final end = to - const Offset(gap, 0);
    final control = Offset((start.dx + end.dx) / 2, start.dy - 46);
    final stroke = Paint()
      ..color = AppTheme.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy),
      stroke,
    );
    // The head follows the curve's direction where it lands.
    final direction = (end - control) / (end - control).distance;
    final normal = Offset(-direction.dy, direction.dx);
    const length = 14.0;
    canvas.drawPath(
      Path()
        ..moveTo(
          (end - direction * length + normal * length * 0.7).dx,
          (end - direction * length + normal * length * 0.7).dy,
        )
        ..lineTo(end.dx, end.dy)
        ..lineTo(
          (end - direction * length - normal * length * 0.7).dx,
          (end - direction * length - normal * length * 0.7).dy,
        ),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_Arrow old) => old.from != from || old.to != to;
}
