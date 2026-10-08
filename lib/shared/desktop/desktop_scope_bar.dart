import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';

import 'desktop_metrics.dart';
import 'desktop_popup.dart' show DesktopChoice;
import 'desktop_theme.dart';

/// A scope bar: narrows a list to one of a few scopes, all visible (the
/// vault table's All / Expiring / Files / Secrets). Like Finder's search
/// scope bar rather than a segmented control, which is for settings.
///
/// - macOS: recessed buttons, the chosen one on a grey fill. (macos_ui has
///   none; its segmented control is `DesktopSegmented`.)
/// - Windows: a row of Fluent `ToggleButton`s.
/// - Linux: Material `ChoiceChip`s in the Yaru theme.
class DesktopScopeBar<T> extends StatelessWidget {
  const DesktopScopeBar({
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
      DesktopKit.macos => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          for (final c in choices)
            _RecessedButton(
              label: c.label,
              selected: c.value == value,
              onTap: () => onChanged(c.value),
            ),
        ],
      ),
      DesktopKit.fluent => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          for (final c in choices)
            fl.ToggleButton(
              checked: c.value == value,
              onChanged: (_) => onChanged(c.value),
              child: Text(c.label),
            ),
        ],
      ),
      DesktopKit.yaru => Wrap(
        spacing: 6,
        children: [
          for (final c in choices)
            ChoiceChip(
              label: Text(c.label),
              selected: c.value == value,
              showCheckmark: false,
              onSelected: (_) => onChanged(c.value),
            ),
        ],
      ),
    };
  }
}

/// A macOS recessed (scope) button: no border; the chosen one sits on a
/// grey fill, and hovering shows a lighter one.
class _RecessedButton extends StatefulWidget {
  const _RecessedButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RecessedButton> createState() => _RecessedButtonState();
}

class _RecessedButtonState extends State<_RecessedButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            // 24 pt: the smallest pointer target (WCAG 2.5.8).
            height: DesktopMetrics.tableHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? colors.innerSeparator
                  : _hovered
                  ? colors.zebra
                  : null,
              borderRadius: const BorderRadius.all(
                Radius.circular(DesktopMetrics.fieldRadius),
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: DesktopMetrics.labelSize,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? colors.text : colors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
