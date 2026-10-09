import 'package:flutter/widgets.dart';

import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// A classic desktop form (sheets, Settings): labels right-aligned in a
/// fixed column, controls beside them, rows evenly spaced.
class DesktopForm extends StatelessWidget {
  const DesktopForm({
    super.key,
    required this.children,
    this.labelWidth = DesktopMetrics.formLabelWidth,
  });

  final List<Widget> children;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final macos = context.desktopKit == DesktopKit.macos;
    return _FormScope(
      labelWidth: labelWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        // macOS rows are a fixed pitch instead (see DesktopFormRow); other
        // children (a strength meter, a message) get a gap below them so the
        // next field's focus ring doesn't touch them.
        spacing: macos ? 0 : DesktopMetrics.formRowGap,
        children: [
          for (final child in children)
            macos && child is! DesktopFormRow
                ? Padding(
                    padding: const EdgeInsets.only(
                      bottom: DesktopMetrics.formNoteGap,
                    ),
                    child: child,
                  )
                : child,
        ],
      ),
    );
  }
}

/// One row of a [DesktopForm]: "[label]:" then [child]. [note] is a line of
/// secondary text under the control (where a value came from, a hint);
/// [error], when set, takes its place in the danger colour.
class DesktopFormRow extends StatelessWidget {
  const DesktopFormRow({
    super.key,
    required this.label,
    required this.child,
    this.note,
    this.error,
    this.multiline = false,
  });

  final String label;
  final Widget child;
  final String? note;
  final String? error;

  /// The control is taller than one line (a text area): the label lines up
  /// with its first line instead of its middle.
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final labelWidth =
        context.dependOnInheritedWidgetOfExactType<_FormScope>()?.labelWidth ??
        DesktopMetrics.formLabelWidth;
    final error = this.error;
    final note = error ?? this.note;
    final row = Row(
      crossAxisAlignment: multiline
          ? CrossAxisAlignment.baseline
          : CrossAxisAlignment.center,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // macos_ui keeps room for the focus ring around a text field, so a
        // field is taller than a pop-up of the same visible height. Every
        // row is at least this tall, so rows keep an even pitch whatever
        // control they hold.
        if (context.desktopKit == DesktopKit.macos)
          const SizedBox(height: DesktopMetrics.formRowHeight),
        SizedBox(
          width: labelWidth,
          child: Text(
            '$label:',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: DesktopMetrics.bodySize,
              color: colors.text,
            ),
          ),
        ),
        const SizedBox(width: DesktopMetrics.formLabelGap),
        Expanded(child: child),
      ],
    );
    if (note == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 3,
      children: [
        row,
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: labelWidth + DesktopMetrics.formLabelGap,
          ),
          child: Text(
            note,
            style: TextStyle(
              fontSize: DesktopMetrics.secondarySize,
              color: error != null ? colors.danger : colors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _FormScope extends InheritedWidget {
  const _FormScope({required this.labelWidth, required super.child});

  final double labelWidth;

  @override
  bool updateShouldNotify(_FormScope oldWidget) =>
      labelWidth != oldWidget.labelWidth;
}
