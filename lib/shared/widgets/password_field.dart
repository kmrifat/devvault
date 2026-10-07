import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A labelled password field with a reveal toggle, built from bc_ui's
/// compound text field so label, description and error stay wired
/// together. ([BCPasswordInput] has the toggle but isn't a text-field part.)
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.description,
    this.error,
    this.autofocus = false,
    this.isDisabled = false,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final String? description;

  /// Shown instead of [description] and marks the field invalid.
  final String? error;
  final bool autofocus;
  final bool isDisabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    return BCTextField(
      isInvalid: error != null,
      isDisabled: widget.isDisabled,
      children: [
        BCTextFieldLabel(widget.label),
        BCTextFieldInput(
          controller: widget.controller,
          focusNode: widget.focusNode,
          obscureText: !_revealed,
          autofocus: widget.autofocus,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          suffix: BCButton(
            variant: BCButtonVariant.ghost,
            size: BCButtonSize.sm,
            isIconOnly: true,
            onPressed: () => setState(() => _revealed = !_revealed),
            child: Icon(
              _revealed ? LucideIcons.eyeOff : LucideIcons.eye,
              semanticLabel: _revealed ? 'Hide password' : 'Show password',
            ),
          ),
        ),
        if (error != null)
          BCTextFieldError(error)
        else if (widget.description != null)
          BCTextFieldDescription(widget.description!),
      ],
    );
  }
}
