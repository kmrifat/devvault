import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;
import 'package:yaru/yaru.dart' as yaru;

import 'desktop_metrics.dart';
import 'desktop_symbols.dart';
import 'desktop_theme.dart';

/// The toolbar's search field: a `MacosTextField` with a search icon and
/// clear button, a Fluent `TextBox` with a search icon, or
/// `YaruSearchField`. [onChanged] gets every edit,
/// including clearing it.
class DesktopSearchField extends StatelessWidget {
  const DesktopSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.placeholder = 'Search',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final kit = context.desktopKit;
    return Semantics(
      label: 'Search',
      textField: true,
      child: switch (kit) {
        // A text field rather than MacosSearchField, which never reports
        // the query going empty and brings a results overlay.
        DesktopKit.macos => mac.MacosTextField(
          controller: controller,
          focusNode: focusNode,
          placeholder: placeholder,
          placeholderStyle: TextStyle(color: colors.tertiaryText),
          autocorrect: false,
          clearButtonMode: mac.OverlayVisibilityMode.editing,
          prefix: Padding(
            padding: const EdgeInsetsDirectional.only(start: 6),
            child: DesktopIcon(DesktopSymbol.search, size: 13),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: colors.toolbarField,
            borderRadius: const BorderRadius.all(
              Radius.circular(DesktopMetrics.menuRadius),
            ),
          ),
          focusedDecoration: const BoxDecoration(
            borderRadius: BorderRadius.all(
              Radius.circular(DesktopMetrics.menuRadius),
            ),
          ),
          onChanged: onChanged,
        ),
        DesktopKit.fluent => SizedBox(
          height: DesktopMetrics.toolbarSearchHeight,
          child: fl.TextBox(
            controller: controller,
            focusNode: focusNode,
            placeholder: placeholder,
            autocorrect: false,
            onChanged: onChanged,
            prefix: Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: DesktopIcon(DesktopSymbol.search, size: 12),
            ),
          ),
        ),
        DesktopKit.yaru => yaru.YaruSearchField(
          controller: controller,
          focusNode: focusNode,
          hintText: placeholder,
          autofocus: false,
          height: DesktopMetrics.toolbarSearchHeight,
          // Yaru's default padding is for its 34 pt field; at 28 pt it
          // pushes the text below the middle.
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          onChanged: onChanged,
          onClear: () {
            controller.clear();
            onChanged('');
          },
        ),
      },
    );
  }
}
