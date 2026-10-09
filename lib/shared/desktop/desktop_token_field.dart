import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop_metrics.dart';
import 'desktop_theme.dart';

/// A token field for tags: each tag is a pill, and the user types new ones
/// at the end. Return or a comma adds the typed tag; Backspace in the empty
/// input removes the last one; a pill's × removes that one.
///
/// No kit has one, so DevVault draws it in its own colours, sized like the
/// kit's text fields (22 pt on macOS).
class DesktopTokenField extends StatefulWidget {
  const DesktopTokenField({
    super.key,
    required this.tokens,
    required this.onChanged,
    this.placeholder,
  });

  final List<String> tokens;
  final ValueChanged<List<String>> onChanged;
  final String? placeholder;

  @override
  State<DesktopTokenField> createState() => _DesktopTokenFieldState();
}

class _DesktopTokenFieldState extends State<DesktopTokenField> {
  final _input = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _onKey);

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String text) {
    final tag = text.trim();
    _input.clear();
    if (tag.isEmpty || widget.tokens.contains(tag)) return;
    widget.onChanged([...widget.tokens, tag]);
  }

  void _remove(String tag) => widget.onChanged([...widget.tokens]..remove(tag));

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace ||
        _input.text.isNotEmpty ||
        widget.tokens.isEmpty) {
      return KeyEventResult.ignored;
    }
    _remove(widget.tokens.last);
    return KeyEventResult.handled;
  }

  void _onChanged(String text) {
    if (text.contains(',')) _commit(text.replaceAll(',', ''));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final style = DefaultTextStyle.of(context).style
        .copyWith(fontSize: DesktopMetrics.bodySize, color: colors.text);
    return GestureDetector(
      onTap: _focus.requestFocus,
      child: ListenableBuilder(
        listenable: _focus,
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            color: colors.field,
            border: Border.all(
              color: _focus.hasFocus ? colors.accent : colors.fieldStroke,
              width: _focus.hasFocus ? 1 : 0.5,
            ),
            borderRadius: const BorderRadius.all(
              Radius.circular(DesktopMetrics.fieldRadius),
            ),
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesktopMetrics.controlHeight - 6,
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tag in widget.tokens)
                  _Token(tag: tag, onRemove: () => _remove(tag)),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 60,
                    maxWidth: 240,
                  ),
                  child: IntrinsicWidth(
                    child: Material(
                      type: MaterialType.transparency,
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        style: style,
                        cursorColor: colors.accent,
                        cursorWidth: 1,
                        onChanged: _onChanged,
                        onSubmitted: (text) {
                          _commit(text);
                          _focus.requestFocus();
                        },
                        // The box above is the field's border. Yaru's
                        // theme would otherwise outline the input again.
                        decoration:
                            InputDecoration.collapsed(
                              hintText: widget.tokens.isEmpty
                                  ? widget.placeholder
                                  : null,
                              hintStyle: style.copyWith(
                                color: colors.tertiaryText,
                              ),
                              filled: false,
                            ).copyWith(
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Token extends StatelessWidget {
  const _Token({required this.tag, required this.onRemove});

  final String tag;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return Semantics(
      label: tag,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.15),
          borderRadius: const BorderRadius.all(
            Radius.circular(DesktopMetrics.tokenRadius),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 1, 3, 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tag,
                style: TextStyle(fontSize: 12, color: colors.accentIcon),
              ),
              const SizedBox(width: 2),
              Semantics(
                button: true,
                label: 'Remove $tag',
                child: GestureDetector(
                  onTap: onRemove,
                  child: Icon(Icons.close, size: 11, color: colors.accentIcon),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
