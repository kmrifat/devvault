import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_theme.dart';

/// One radio button: `MacosRadioButton`, Fluent `RadioButton` or a
/// Yaru-themed `Radio`. The screen keeps the group's state: [selected] says
/// whether this one is chosen, and [onSelected] is called when it is
/// clicked. Null [onSelected] disables it.
///
/// It is only the circle; the screen draws the label (and usually makes the
/// whole row clickable too, as the conflict sheet does).
class DesktopRadio extends StatelessWidget {
  const DesktopRadio({
    super.key,
    required this.selected,
    required this.onSelected,
    this.semanticLabel,
  });

  final bool selected;
  final VoidCallback? onSelected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final onSelected = this.onSelected;
    // The kits' Fluent and Material radios read the group from a
    // RadioGroup: a group of one, chosen or not.
    void changed(bool? _) => onSelected?.call();
    return switch (context.desktopKit) {
      DesktopKit.macos => mac.MacosRadioButton<bool>(
        value: true,
        groupValue: selected,
        size: 14,
        semanticLabel: semanticLabel,
        onChanged: onSelected == null ? null : changed,
      ),
      DesktopKit.fluent => RadioGroup<bool>(
        groupValue: selected ? true : null,
        onChanged: changed,
        child: fl.RadioButton<bool>(
          value: true,
          enabled: onSelected != null,
          semanticLabel: semanticLabel,
        ),
      ),
      DesktopKit.yaru => Semantics(
        label: semanticLabel,
        child: RadioGroup<bool>(
          groupValue: selected ? true : null,
          onChanged: changed,
          child: Radio<bool>(
            value: true,
            enabled: onSelected != null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    };
  }
}
