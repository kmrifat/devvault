import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_theme.dart';

/// An indeterminate progress spinner for work that takes a moment (reading
/// a file, saving): `ProgressCircle` on macOS, Fluent's `ProgressRing`, or
/// a Yaru-themed `CircularProgressIndicator`. [semanticLabel] says what is
/// happening to screen readers.
class DesktopProgress extends StatelessWidget {
  const DesktopProgress({super.key, this.size = 16, this.semanticLabel});

  /// Edge length of the spinner.
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox.square(
        dimension: size,
        child: switch (context.desktopKit) {
          DesktopKit.macos => mac.ProgressCircle(radius: size / 2),
          DesktopKit.fluent => const fl.ProgressRing(strokeWidth: 2),
          DesktopKit.yaru => const CircularProgressIndicator(strokeWidth: 2),
        },
      ),
    );
  }
}
