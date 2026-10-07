import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'mono_text.dart';

/// A labelled secret (password, client secret, private key) that stays
/// masked until the user reveals it.
///
/// Copying goes through [onCopy], so the caller can route it through the
/// clipboard guard that clears it again. This widget never touches the
/// clipboard itself.
class SecretRow extends StatefulWidget {
  const SecretRow({
    super.key,
    required this.label,
    required this.secret,
    this.onCopy,
    this.description,
  });

  final String label;
  final String secret;
  final ValueChanged<String>? onCopy;

  /// Secondary line under the label, e.g. "Entered by you".
  final String? description;

  static const String mask = '••••••••••••';

  @override
  State<SecretRow> createState() => _SecretRowState();
}

class _SecretRowState extends State<SecretRow> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    return Row(
      spacing: BCSpacing.sm,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: BCSpacing.xxs,
            children: [
              BCText(
                widget.description == null
                    ? widget.label
                    : '${widget.label} · ${widget.description}',
                type: BCTextType.bodySm,
                color: BCTextColor.muted,
              ),
              _revealed
                  ? MonoText(widget.secret, middleEllipsis: true)
                  : Semantics(
                      label: '${widget.label}, hidden',
                      excludeSemantics: true,
                      child: Text(
                        SecretRow.mask,
                        style: TextStyle(
                          color: bc.foreground,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
            ],
          ),
        ),
        BCButton(
          variant: BCButtonVariant.ghost,
          size: BCButtonSize.sm,
          isIconOnly: true,
          onPressed: () => setState(() => _revealed = !_revealed),
          child: Icon(
            _revealed ? LucideIcons.eyeOff : LucideIcons.eye,
            semanticLabel: _revealed ? 'Hide' : 'Reveal',
          ),
        ),
        if (widget.onCopy != null)
          BCButton(
            variant: BCButtonVariant.ghost,
            size: BCButtonSize.sm,
            isIconOnly: true,
            onPressed: () => widget.onCopy!(widget.secret),
            child: const Icon(LucideIcons.copy, semanticLabel: 'Copy'),
          ),
      ],
    );
  }
}
