import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_theme.dart';

/// An indeterminate spinner, for work that takes a moment (sealing a
/// pairing code, re-encrypting): `ProgressCircle`, Fluent `ProgressRing`, or
/// a Yaru-themed `CircularProgressIndicator`. [size] is its diameter.
class DesktopProgress extends StatelessWidget {
  const DesktopProgress({super.key, this.size = 16, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: switch (context.desktopKit) {
        DesktopKit.macos => mac.ProgressCircle(
          radius: size / 2,
          semanticLabel: semanticLabel,
        ),
        DesktopKit.fluent => fl.ProgressRing(
          strokeWidth: size / 8,
          semanticLabel: semanticLabel,
        ),
        DesktopKit.yaru => CircularProgressIndicator(
          strokeWidth: size / 8,
          semanticsLabel: semanticLabel,
        ),
      },
    );
  }
}
