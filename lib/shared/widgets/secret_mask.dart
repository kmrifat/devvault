import 'package:flutter/widgets.dart';

/// A hidden secret: eight round dots. Drawn rather than typed, so they're
/// the same clear size in every font; the text bullets they replace were
/// about 4 pt across and hard to see (P7-02). Always eight, whatever the
/// secret's length, so the mask says nothing about it.
///
/// Screen readers hear [semanticLabel] ("Key password, hidden"), or
/// nothing when the row around it already says so.
class SecretMask extends StatelessWidget {
  const SecretMask({super.key, this.color, this.semanticLabel});

  static const int dots = 8;
  static const double dotSize = 6;
  static const double gap = 4;

  /// Defaults to the surrounding text's colour.
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fill =
        color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    final mask = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: gap,
      children: [
        for (var i = 0; i < dots; i++)
          DecoratedBox(
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: const SizedBox.square(dimension: dotSize),
          ),
      ],
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: mask)
        : Semantics(label: label, excludeSemantics: true, child: mask);
  }
}
