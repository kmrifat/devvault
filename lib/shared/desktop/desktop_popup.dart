import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import 'desktop_theme.dart';

/// What a macOS pop-up menu row needs beyond its label (check-mark column
/// and padding), measured from macos_ui 2.2.2.
const double _macosMenuExtraWidth = 36;

/// One choice in a [DesktopPopup] or [DesktopSegmented].
@immutable
class DesktopChoice<T> {
  const DesktopChoice(this.value, this.label);

  final T value;
  final String label;
}

/// A pop-up button: pick one of a fixed set of choices (item type, auto-lock
/// time). For a value the user may also type, use `DesktopComboBox`.
///
/// `MacosPopupButton`, Fluent `ComboBox`, or Material's `DropdownButton`
/// in the Yaru theme. [value] null shows [placeholder].
class DesktopPopup<T> extends StatelessWidget {
  const DesktopPopup({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.placeholder,
  });

  final T? value;
  final List<DesktopChoice<T>> choices;

  /// Null disables the button.
  final ValueChanged<T>? onChanged;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final hint = placeholder == null ? null : Text(placeholder!);
    return switch (context.desktopKit) {
      DesktopKit.macos => mac.MacosPopupButton<T>(
        value: value,
        hint: hint,
        // The menu is as wide as the button, but its rows also hold a
        // check-mark column the button doesn't, so the widest row would
        // overflow. Reserving that width on the button keeps them equal.
        selectedItemBuilder: (context) => [
          for (final c in choices)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                end: _macosMenuExtraWidth,
              ),
              child: Text(c.label),
            ),
        ],
        onChanged: onChanged == null
            ? null
            : (v) {
                if (v != null) onChanged(v);
              },
        items: [
          for (final c in choices)
            mac.MacosPopupMenuItem(value: c.value, child: Text(c.label)),
        ],
      ),
      DesktopKit.fluent => fl.ComboBox<T>(
        value: value,
        placeholder: hint,
        onChanged: onChanged == null
            ? null
            : (v) {
                if (v != null) onChanged(v);
              },
        items: [
          for (final c in choices)
            fl.ComboBoxItem(value: c.value, child: Text(c.label)),
        ],
      ),
      DesktopKit.yaru => DropdownButton<T>(
        value: value,
        hint: hint,
        isDense: true,
        onChanged: onChanged == null
            ? null
            : (v) {
                if (v != null) onChanged(v);
              },
        items: [
          for (final c in choices)
            DropdownMenuItem(value: c.value, child: Text(c.label)),
        ],
      ),
    };
  }
}
