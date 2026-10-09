import 'package:fluent_ui/fluent_ui.dart' as fl;
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart' as mac;

import '../../app/theme.dart' show AppText;
import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// A text field drawn by the desktop kit: `MacosTextField`, Fluent's
/// `TextBox`, or a Yaru-themed `TextField`.
///
/// With [obscureText] it is a secure field: masked, with autocorrect and
/// suggestions off. (Fluent's `PasswordBox` can't turn those off, so
/// Windows uses a masked `TextBox`.)
///
/// [mono] sets the text in JetBrains Mono, for keys, IDs and file names.
///
/// With [maxLines] above one it is a text area, where Return types a new
/// line, unless it has [onSubmitted]: then the text only wraps, it is still
/// one value (a recovery key), and Return submits it.
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
    this.maxLines = 1,
    this.minLines,
    this.autocorrect = true,
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

  /// More than one for a text area (notes, lists of IDs). A secure field
  /// is always one line.
  final int maxLines;
  final int? minLines;

  /// False for keys and codes: no autocorrect or suggestions. A secure
  /// field never has them.
  final bool autocorrect;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final corrects = autocorrect && !obscureText;
    // A multi-line field defaults to the multiline input type and the
    // newline action, so Return types a new line. Plain text with Done
    // makes Return submit instead; the text still wraps.
    final wrapsOneValue = maxLines > 1 && onSubmitted != null;
    final keyboardType = wrapsOneValue ? TextInputType.text : null;
    final textInputAction = wrapsOneValue ? TextInputAction.done : null;
    final style = mono ? AppText.mono(context, fontSize: 12.5) : null;
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
        placeholderStyle: TextStyle(
          color: colors.tertiaryText,
          fontSize: DesktopMetrics.bodySize,
        ),
        // Fields are DesktopMetrics.fieldHeight tall, like the pop-ups and
        // combo boxes beside them.
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        obscureText: obscureText,
        enabled: enabled,
        autofocus: autofocus,
        autocorrect: corrects,
        enableSuggestions: corrects,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        style:
            monoStyle ??
            TextStyle(fontSize: DesktopMetrics.bodySize, color: colors.text),
        suffix: suffix,
        maxLines: maxLines,
        minLines: minLines,
      ),
      DesktopKit.fluent => fl.TextBox(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        obscureText: obscureText,
        enabled: enabled,
        autocorrect: corrects,
        enableSuggestions: corrects,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofocus: autofocus,
        style: monoStyle,
        suffix: suffix,
        maxLines: maxLines,
        minLines: minLines,
      ),
      DesktopKit.yaru => TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        obscureText: obscureText,
        enabled: enabled,
        autofocus: autofocus,
        autocorrect: corrects,
        enableSuggestions: corrects,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        style: monoStyle,
        maxLines: maxLines,
        minLines: minLines,
        decoration: InputDecoration(
          hintText: placeholder,
          // Material colours the hint with the field's style, which made a
          // mono placeholder look like a typed value.
          hintStyle: style?.copyWith(color: colors.tertiaryText),
          isDense: true,
          suffixIcon: suffix,
          // Material keeps a 40 px square for it, which made a combo box
          // taller than a text field.
          suffixIconConstraints: const BoxConstraints(
            minWidth: DesktopMetrics.yaruFieldButtonSize,
            minHeight: DesktopMetrics.yaruFieldButtonSize,
          ),
        ),
      ),
    };
  }
}
