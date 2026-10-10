import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaru/yaru.dart' as yaru;

import 'desktop_macos_menu.dart';
import 'desktop_metrics.dart';
import 'desktop_text_field.dart';
import 'desktop_theme.dart';

/// A combo box: a text field that suggests values from a menu but takes
/// whatever the user types (platform, environment).
///
/// The value is the field's text. Typing reports every change through
/// [onChanged], and picking a suggestion replaces the text with it. The
/// suggestions are only suggestions: nothing is chosen for the user.
///
/// - macOS: `MacosTextField` with a chevron inside its trailing edge that
///   drops a menu under the field, like `NSComboBox`. (macos_ui has no
///   combo box, and its pull-down button draws a second caret.)
/// - Windows: Fluent `TextBox` with a chevron that opens a menu flyout,
///   like `EditableComboBox` (which can't start empty).
/// - Linux: Yaru-themed `TextField` with a chevron menu.
class DesktopComboBox extends StatefulWidget {
  const DesktopComboBox({
    super.key,
    required this.value,
    required this.suggestions,
    required this.onChanged,
    this.placeholder,
    this.enabled = true,
    this.menuLabel = 'Suggestions',
  });

  final String value;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final bool enabled;

  /// What screen readers call the suggestions button.
  final String menuLabel;

  @override
  State<DesktopComboBox> createState() => _DesktopComboBoxState();
}

class _DesktopComboBoxState extends State<DesktopComboBox> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(DesktopComboBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pick(String suggestion) {
    _controller.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    widget.onChanged(suggestion);
  }

  @override
  Widget build(BuildContext context) {
    final canPick = widget.enabled && widget.suggestions.isNotEmpty;
    return switch (context.desktopKit) {
      DesktopKit.macos => _MacosComboMenu(
        suggestions: canPick ? widget.suggestions : const [],
        label: widget.menuLabel,
        onPick: _pick,
        fieldBuilder: (suffix) => _field(suffix: suffix),
      ),
      DesktopKit.fluent => _field(
        suffix: canPick
            ? fl.DropDownButton(
                items: [
                  for (final s in widget.suggestions)
                    fl.MenuFlyoutItem(text: Text(s), onPressed: () => _pick(s)),
                ],
                buttonBuilder: (context, onOpen) => Semantics(
                  button: true,
                  label: widget.menuLabel,
                  child: fl.IconButton(
                    icon: const fl.WindowsIcon(
                      fl.WindowsIcons.chevron_down,
                      size: 8,
                    ),
                    onPressed: onOpen,
                  ),
                ),
              )
            : null,
      ),
      DesktopKit.yaru => _field(
        suffix: canPick
            ? PopupMenuButton<String>(
                tooltip: widget.menuLabel,
                icon: const Icon(yaru.YaruIcons.pan_down),
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(
                    DesktopMetrics.yaruFieldButtonSize,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelected: _pick,
                itemBuilder: (context) => [
                  for (final s in widget.suggestions)
                    PopupMenuItem(value: s, child: Text(s)),
                ],
              )
            : null,
      ),
    };
  }

  Widget _field({Widget? suffix}) => DesktopTextField(
    controller: _controller,
    placeholder: widget.placeholder,
    onChanged: widget.onChanged,
    enabled: widget.enabled,
    suffix: suffix,
  );
}

/// The macOS combo box: the field anchors a menu of suggestions in the
/// macOS menu style, opened by the chevron (or ↓ in the field).
class _MacosComboMenu extends StatelessWidget {
  const _MacosComboMenu({
    required this.suggestions,
    required this.label,
    required this.onPick,
    required this.fieldBuilder,
  });

  final List<String> suggestions;
  final String label;
  final ValueChanged<String> onPick;
  final Widget Function(Widget? suffix) fieldBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return LayoutBuilder(
      builder: (context, constraints) => MenuAnchor(
        style: MacosMenuStyle.panel(colors),
        clipBehavior: Clip.antiAlias,
        menuChildren: [
          MacosMenuStyle.surface(
            context,
            children: [
              for (final s in suggestions)
                MacosMenuStyle.item(
                  context,
                  label: s,
                  width: constraints.maxWidth,
                  onPressed: () => onPick(s),
                ),
            ],
          ),
        ],
        builder: (context, menu, _) {
          void toggle() => menu.isOpen ? menu.close() : menu.open();
          return CallbackShortcuts(
            bindings: {
              if (suggestions.isNotEmpty)
                const SingleActivator(LogicalKeyboardKey.arrowDown): menu.open,
            },
            child: fieldBuilder(
              suggestions.isEmpty
                  ? null
                  : Semantics(
                      button: true,
                      label: label,
                      // The whole end of the field opens the menu, not
                      // just the chevron: a full-height target.
                      child: GestureDetector(
                        onTap: toggle,
                        behavior: HitTestBehavior.opaque,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.basic,
                          child: SizedBox(
                            width: DesktopMetrics.fieldHeight,
                            height: DesktopMetrics.fieldHeight - 6,
                            child: Icon(
                              CupertinoIcons.chevron_down,
                              size: 12,
                              color: colors.secondaryText,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}
