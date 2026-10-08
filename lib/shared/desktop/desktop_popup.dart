import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

import 'desktop_macos_menu.dart';
import 'desktop_metrics.dart';
import 'desktop_theme.dart';

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
/// On macOS a DevVault-drawn pop-up as tall as a text field, Fluent
/// `ComboBox` on Windows, or Material's `DropdownButton`
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
      DesktopKit.macos => _MacosPopup<T>(
        value: value,
        choices: choices,
        onChanged: onChanged,
        placeholder: placeholder,
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

/// A macOS pop-up button as tall as the text fields beside it
/// ([DesktopMetrics.fieldHeight]): the choice and the up-down chevrons in a
/// field-like box, opening a macOS menu with a check by the chosen one.
/// (macos_ui's is a fixed 20 pt.)
class _MacosPopup<T> extends StatefulWidget {
  const _MacosPopup({
    required this.value,
    required this.choices,
    required this.onChanged,
    required this.placeholder,
  });

  final T? value;
  final List<DesktopChoice<T>> choices;
  final ValueChanged<T>? onChanged;
  final String? placeholder;

  @override
  State<_MacosPopup<T>> createState() => _MacosPopupState<T>();
}

class _MacosPopupState<T> extends State<_MacosPopup<T>> {
  final _menu = MenuController();
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final onChanged = widget.onChanged;
    final enabled = onChanged != null;
    final selected = widget.choices
        .where((c) => c.value == widget.value)
        .firstOrNull;
    final label = selected?.label ?? widget.placeholder ?? '';
    void toggle() => _menu.isOpen ? _menu.close() : _menu.open();
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight =
            constraints.hasBoundedWidth &&
            constraints.minWidth == constraints.maxWidth;
        final box = Container(
          height: DesktopMetrics.fieldHeight,
          constraints: const BoxConstraints(minWidth: 120),
          padding: const EdgeInsets.only(left: 9, right: 6),
          decoration: BoxDecoration(
            color: _hovered && enabled ? colors.groupBox : colors.field,
            border: Border.all(color: colors.fieldStroke, width: 0.5),
            borderRadius: const BorderRadius.all(
              Radius.circular(DesktopMetrics.fieldRadius),
            ),
          ),
          child: Row(
            // Given a set width (a form column), the chevrons sit at its end;
            // otherwise the button is as wide as its choice.
            mainAxisSize: tight ? MainAxisSize.max : MainAxisSize.min,
            spacing: 8,
            children: [
              Flexible(
                fit: tight ? FlexFit.tight : FlexFit.loose,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DesktopMetrics.bodySize,
                    color: selected == null ? colors.tertiaryText : colors.text,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_up_chevron_down,
                size: 12,
                color: colors.secondaryText,
              ),
            ],
          ),
        );
        return MenuAnchor(
          controller: _menu,
          style: MacosMenuStyle.panel(colors),
          menuChildren: [
            for (final c in widget.choices)
              MacosMenuStyle.item(
                context,
                label: c.label,
                width: constraints.hasBoundedWidth ? constraints.maxWidth : 160,
                checked: c.value == widget.value,
                onPressed: () => onChanged?.call(c.value),
              ),
          ],
          child: Semantics(
            button: true,
            enabled: enabled,
            label: label,
            child: FocusableActionDetector(
              enabled: enabled,
              mouseCursor: SystemMouseCursors.basic,
              onShowHoverHighlight: (on) => setState(() => _hovered = on),
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) => toggle(),
                ),
              },
              child: GestureDetector(
                onTap: enabled ? toggle : null,
                child: Opacity(opacity: enabled ? 1 : 0.5, child: box),
              ),
            ),
          ),
        );
      },
    );
  }
}
