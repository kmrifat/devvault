import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Monospace text for key IDs, fingerprints, filenames and recovery keys.
///
/// When [middleEllipsis] is set and the text doesn't fit on one line, the
/// middle is replaced with `…` so both ends stay visible. The start and end
/// of a fingerprint or filename are what people compare.
class MonoText extends StatelessWidget {
  const MonoText(
    this.text, {
    super.key,
    this.style,
    this.middleEllipsis = false,
    this.selectable = false,
  });

  final String text;

  /// Merged over [AppText.mono].
  final TextStyle? style;

  final bool middleEllipsis;

  /// Lets the user select and copy the text. Never use this for secrets;
  /// secrets are copied through the clipboard guard.
  final bool selectable;

  static const String ellipsis = '…';

  @override
  Widget build(BuildContext context) {
    final resolved = AppText.mono(context).merge(style);
    if (!middleEllipsis) return _text(text, resolved);

    return LayoutBuilder(
      builder: (context, constraints) => _text(
        fitMiddle(
          text,
          resolved,
          constraints.maxWidth,
          MediaQuery.textScalerOf(context),
          Directionality.of(context),
        ),
        resolved,
      ),
    );
  }

  Widget _text(String value, TextStyle style) => selectable
      ? SelectableText(value, style: style, maxLines: 1)
      : Text(value, style: style, maxLines: 1, softWrap: false);

  /// The longest `head…tail` form of [text] that fits in [maxWidth], keeping
  /// head and tail as even as possible. Returns [text] unchanged when it
  /// fits.
  static String fitMiddle(
    String text,
    TextStyle style,
    double maxWidth,
    TextScaler scaler,
    TextDirection direction,
  ) {
    double widthOf(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    if (!maxWidth.isFinite || widthOf(text) <= maxWidth) return text;

    String shortened(int keep) {
      final head = (keep + 1) ~/ 2;
      final tail = keep ~/ 2;
      return '${text.substring(0, head)}$ellipsis'
          '${text.substring(text.length - tail)}';
    }

    // Binary search for the most characters that still fit.
    var low = 0;
    var high = text.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (widthOf(shortened(mid)) <= maxWidth) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return shortened(low);
  }
}
