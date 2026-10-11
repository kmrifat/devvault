import 'package:flutter/widgets.dart';

import '../../app/theme.dart';

/// DevVault's mark, as on the app icon: a stack of credential files sealed
/// by a lock, white on the rose tile. Decorative; the screen's title names
/// the app. Below 40 px the back file and the `KEY=value` lines blur, so it
/// draws [AppMarkPainter]'s simple mark instead.
class AppMark extends StatelessWidget {
  const AppMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          gradient: AppTheme.brandGradient,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(Radius.circular(size * 0.225)),
          ),
        ),
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: AppMarkPainter(simple: size < 40)),
        ),
      ),
    );
  }
}

/// The mark without its tile, drawn on a 100 × 100 grid scaled to the
/// canvas. The ring around the badge, the `KEY=value` lines and the fold
/// are cut out of the white, so whatever is behind (the rose tile, or
/// Android's adaptive background) shows through them. Also renders the app
/// icon (`test/tool/app_icon_test.dart`).
class AppMarkPainter extends CustomPainter {
  const AppMarkPainter({this.simple = false});

  /// One file and a larger lock, for small sizes.
  final bool simple;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    if (simple) {
      _paintSimple(canvas);
    } else {
      _paintFull(canvas);
    }
    canvas.restore();
  }

  void _paintFull(Canvas canvas) {
    canvas.translate(-6, -4);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 106, 104), Paint());
    // The file behind.
    canvas.drawRRect(
      RRect.fromLTRBR(24, 20, 64, 72, const Radius.circular(5)),
      Paint()..color = AppTheme.brandGlyph.withValues(alpha: 0.45),
    );
    // The front file, its top right corner folded.
    canvas.drawPath(
      _file(36, 28, 72, 82, fold: 10, radius: 5),
      Paint()..color = AppTheme.brandGlyph,
    );
    canvas.drawPath(_fold(72, 28, 10), _foldPaint);
    // KEY=value lines: a short key, a gap, a longer value.
    final line = Paint()
      ..blendMode = BlendMode.clear
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    for (final (y, segments) in const [
      (45.0, [(44.0, 49.0), (53.0, 64.0)]),
      (53.0, [(44.0, 47.0), (51.0, 64.0)]),
      (61.0, [(44.0, 50.0)]),
    ]) {
      for (final (x1, x2) in segments) {
        canvas.drawLine(Offset(x1, y), Offset(x2, y), line);
      }
    }
    // The ring that sets the badge apart from the files.
    canvas.drawCircle(
      const Offset(70, 74),
      18,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();

    _paintLock(
      canvas,
      centre: const Offset(70, 74),
      badge: 14.5,
      body: const Rect.fromLTWH(61, 71, 18, 12),
      shackle: 5.5,
      stroke: 2.6,
      keyhole: 1.9,
    );
  }

  void _paintSimple(Canvas canvas) {
    canvas.translate(-10, -6);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 110, 106), Paint());
    canvas.drawPath(
      _file(30, 18, 70, 84, fold: 12, radius: 6),
      Paint()..color = AppTheme.brandGlyph,
    );
    canvas.drawPath(_fold(70, 18, 12), _foldPaint);
    canvas.drawCircle(
      const Offset(70, 72),
      22,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();

    _paintLock(
      canvas,
      centre: const Offset(70, 72),
      badge: 18,
      body: const Rect.fromLTWH(60, 70, 20, 14),
      shackle: 6.5,
      stroke: 3.6,
    );
  }

  /// Lets 30% of what's behind through the folded corner.
  static final _foldPaint = Paint()
    ..color = const Color(0x4D000000)
    ..blendMode = BlendMode.dstOut;

  /// A file: a rounded rectangle whose top right corner is cut by [fold].
  static Path _file(
    double left,
    double top,
    double right,
    double bottom, {
    required double fold,
    required double radius,
  }) => Path()
    ..moveTo(left + radius, top)
    ..lineTo(right - fold, top)
    ..lineTo(right, top + fold)
    ..lineTo(right, bottom - radius)
    ..quadraticBezierTo(right, bottom, right - radius, bottom)
    ..lineTo(left + radius, bottom)
    ..quadraticBezierTo(left, bottom, left, bottom - radius)
    ..lineTo(left, top + radius)
    ..quadraticBezierTo(left, top, left + radius, top)
    ..close();

  /// The folded corner of a file whose top right corner is ([right], [top]).
  static Path _fold(double right, double top, double fold) => Path()
    ..moveTo(right - fold, top)
    ..lineTo(right - fold, top + fold)
    ..lineTo(right, top + fold)
    ..close();

  static void _paintLock(
    Canvas canvas, {
    required Offset centre,
    required double badge,
    required Rect body,
    required double shackle,
    required double stroke,
    double? keyhole,
  }) {
    canvas.drawCircle(centre, badge, Paint()..color = AppTheme.brandInk);
    final shackleBottom = body.top + 1;
    canvas.drawPath(
      Path()
        ..moveTo(centre.dx - shackle, shackleBottom)
        ..lineTo(centre.dx - shackle, shackleBottom - shackle)
        ..arcToPoint(
          Offset(centre.dx + shackle, shackleBottom - shackle),
          radius: Radius.circular(shackle),
        )
        ..lineTo(centre.dx + shackle, shackleBottom),
      Paint()
        ..color = AppTheme.brandGlyph
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(body.height / 4.8)),
      Paint()..color = AppTheme.brandGlyph,
    );
    if (keyhole != null) {
      canvas.drawCircle(
        Offset(centre.dx, body.center.dy - 0.5),
        keyhole,
        Paint()..color = AppTheme.brandInk,
      );
    }
  }

  @override
  bool shouldRepaint(AppMarkPainter old) => old.simple != simple;
}
