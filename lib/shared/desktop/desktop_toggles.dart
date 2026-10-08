import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

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
/// System). `MacosSegmentedControl`, a row of Fluent `ToggleButton`s, or
/// Material's `SegmentedButton` in the Yaru theme.
class DesktopSegmented<T> extends StatefulWidget {
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
  State<DesktopSegmented<T>> createState() => _DesktopSegmentedState<T>();
}

class _DesktopSegmentedState<T> extends State<DesktopSegmented<T>> {
  /// macOS only: its segmented control is driven by a tab controller.
  late final _tabs = mac.MacosTabController(
    length: widget.choices.length,
    initialIndex: _indexOf(widget.value),
  )..addListener(_onTab);

  int _indexOf(T value) {
    final index = widget.choices.indexWhere((c) => c.value == value);
    return index < 0 ? 0 : index;
  }

  void _onTab() {
    final picked = widget.choices[_tabs.index].value;
    if (picked != widget.value) widget.onChanged(picked);
  }

  @override
  void didUpdateWidget(DesktopSegmented<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _indexOf(widget.value);
    if (_tabs.index != index) _tabs.index = index;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (context.desktopKit) {
      DesktopKit.macos => mac.MacosSegmentedControl(
        controller: _tabs,
        tabs: [for (final c in widget.choices) mac.MacosTab(label: c.label)],
      ),
      DesktopKit.fluent => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in widget.choices)
            fl.ToggleButton(
              checked: c.value == widget.value,
              onChanged: (_) => widget.onChanged(c.value),
              child: Text(c.label),
            ),
        ],
      ),
      DesktopKit.yaru => SegmentedButton<T>(
        showSelectedIcon: false,
        selected: {widget.value},
        onSelectionChanged: (s) => widget.onChanged(s.first),
        segments: [
          for (final c in widget.choices)
            ButtonSegment(value: c.value, label: Text(c.label)),
        ],
      ),
    };
  }
}
