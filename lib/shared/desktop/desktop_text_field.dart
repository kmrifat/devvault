import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import '../../app/theme.dart' show AppText;
import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// A single-line text field drawn by the desktop kit: `MacosTextField`,
/// Fluent's `TextBox`, or a Yaru-themed `TextField`.
///
/// With [obscureText] it is a secure field: masked, with autocorrect and
/// suggestions off. (Fluent's `PasswordBox` can't turn those off, so
/// Windows uses a masked `TextBox`.)
///
/// [mono] sets the text in JetBrains Mono, for keys, IDs and file names.
const _macosRadius = BorderRadius.all(
  Radius.circular(DesktopMetrics.fieldRadius),
);

class DesktopTextField extends StatelessWidget {
  const DesktopTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.mono = false,
    this.enabled = true,
    this.autofocus = false,
    this.suffix,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final bool mono;
  final bool enabled;
  final bool autofocus;

  /// A small widget inside the field's trailing edge (a menu button).
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final style = mono ? AppText.mono(context, fontSize: 12) : null;
    final monoStyle = style?.copyWith(color: colors.text);
    return switch (context.desktopKit) {
      DesktopKit.macos => mac.MacosTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        // The kit's default field is black in dark mode and its
        // placeholder doesn't follow dark mode; draw both from the tokens.
        decoration: BoxDecoration(
          color: colors.field,
          border: Border.all(color: colors.fieldStroke, width: 0.5),
          borderRadius: _macosRadius,
        ),
        focusedDecoration: const BoxDecoration(borderRadius: _macosRadius),
        placeholderStyle: TextStyle(color: colors.tertiaryText),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        obscureText: obscureText,
        enabled: enabled,
        autofocus: autofocus,
        autocorrect: !obscureText,
        enableSuggestions: !obscureText,
        style: monoStyle,
        suffix: suffix,
      ),
      DesktopKit.fluent => fl.TextBox(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        obscureText: obscureText,
        enabled: enabled,
        autocorrect: !obscureText,
        enableSuggestions: !obscureText,
        autofocus: autofocus,
        style: monoStyle,
        suffix: suffix,
      ),
      DesktopKit.yaru => TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        obscureText: obscureText,
        enabled: enabled,
        autofocus: autofocus,
        autocorrect: !obscureText,
        enableSuggestions: !obscureText,
        style: monoStyle,
        decoration: InputDecoration(
          hintText: placeholder,
          isDense: true,
          suffixIcon: suffix,
        ),
      ),
    };
  }
}
