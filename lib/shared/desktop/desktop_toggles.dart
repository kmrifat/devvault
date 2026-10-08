import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_metrics.dart';
import 'desktop_popup.dart' show DesktopChoice;
import 'desktop_theme.dart';

/// An on/off switch: `MacosSwitch`, Fluent `ToggleSwitch`, or a Yaru-themed
/// `Switch`. Null [onChanged] disables it.
class DesktopSwitch extends StatelessWidget {
  const DesktopSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: switch (context.desktopKit) {
        DesktopKit.macos => mac.MacosSwitch(
          value: value,
          size: mac.ControlSize.small,
          onChanged: onChanged,
        ),
        DesktopKit.fluent => fl.ToggleSwitch(
          checked: value,
          onChanged: onChanged,
        ),
        DesktopKit.yaru => Switch(value: value, onChanged: onChanged),
      },
    );
  }
}

/// A checkbox with its label; clicking the label toggles it too.
/// `MacosCheckbox`, Fluent `Checkbox`, or a Yaru-themed `Checkbox`.
class DesktopCheckbox extends StatelessWidget {
  const DesktopCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final toggle = onChanged == null ? null : () => onChanged(!value);
    final box = switch (context.desktopKit) {
      DesktopKit.macos => mac.MacosCheckbox(
        value: value,
        onChanged: onChanged == null ? null : (v) => onChanged(v),
      ),
      DesktopKit.fluent => fl.Checkbox(
        checked: value,
        onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
      ),
      DesktopKit.yaru => Checkbox(
        value: value,
        onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
      ),
    };
    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          box,
          const SizedBox(width: 6),
          GestureDetector(onTap: toggle, child: Text(label)),
        ],
      ),
    );
  }
}

/// A segmented control: one of a few choices, all visible (Light / Dark /
/// System). On macOS DevVault draws it in the system's style (macos_ui's
/// `MacosSegmentedControl` crowds its labels against the segment's edge, so
/// they can't be measured for contrast), a row of Fluent `ToggleButton`s on
/// Windows, Material's `SegmentedButton` in the Yaru theme on Linux.
class DesktopSegmented<T> extends StatelessWidget {
  const DesktopSegmented({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
  }) : assert(choices.length > 1);

  final T value;
  final List<DesktopChoice<T>> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return switch (context.desktopKit) {
      DesktopKit.macos => _MacosSegmented<T>(
        value: value,
        choices: choices,
        onChanged: onChanged,
      ),
      DesktopKit.fluent => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in choices)
            fl.ToggleButton(
              checked: c.value == value,
              onChanged: (_) => onChanged(c.value),
              child: Text(c.label),
            ),
        ],
      ),
      DesktopKit.yaru => SegmentedButton<T>(
        showSelectedIcon: false,
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
        segments: [
          for (final c in choices)
            ButtonSegment(value: c.value, label: Text(c.label)),
        ],
      ),
    };
  }
}

/// macOS's segmented control, 22 pt: a grey track, the chosen segment
/// raised in white (lighter grey in dark mode), thin dividers between the
/// others.
class _MacosSegmented<T> extends StatelessWidget {
  const _MacosSegmented({
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final T value;
  final List<DesktopChoice<T>> choices;
  final ValueChanged<T> onChanged;

  /// Each segment's target is this tall, around the 22 pt control: the
  /// 24 × 24 minimum (WCAG 2.5.8).
  static const double _targetHeight = 24;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    const radius = BorderRadius.all(
      Radius.circular(DesktopMetrics.fieldRadius),
    );
    const inset = EdgeInsets.symmetric(
      vertical: (_targetHeight - DesktopMetrics.controlHeight) / 2,
    );
    final selected = choices.indexWhere((c) => c.value == value);
    return SizedBox(
      height: _targetHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: inset,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.toolbarField,
                  borderRadius: radius,
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, c) in choices.indexed) ...[
                if (i > 0)
                  SizedBox(
                    width: 1,
                    height: DesktopMetrics.controlHeight / 2,
                    child: ColoredBox(
                      // No divider beside the chosen segment.
                      color: i == selected || i - 1 == selected
                          ? Colors.transparent
                          : colors.fieldStroke,
                    ),
                  ),
                Semantics(
                  button: true,
                  selected: i == selected,
                  inMutuallyExclusiveGroup: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (c.value != value) onChanged(c.value);
                    },
                    child: Container(
                      margin: inset,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: i == selected
                          ? BoxDecoration(
                              color: colors.selectedSegment,
                              borderRadius: radius,
                              border: Border.all(
                                color: colors.fieldStroke,
                                width: 0.5,
                              ),
                            )
                          : null,
                      child: Text(
                        c.label,
                        style: TextStyle(
                          fontSize: DesktopMetrics.bodySize,
                          // A tight line, so the label keeps clear of the
                          // segment's edge.
                          height: 1,
                          color: colors.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
