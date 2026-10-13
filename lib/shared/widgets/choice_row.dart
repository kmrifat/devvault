import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart'
    show LiquidGlassAlert, LiquidGlassAlertAction, LiquidGlassAlertStyle;

/// A row with a few choices (Settings, the item form). On iPhone
/// ([native]) the row shows the current one and opens UIKit's action sheet
/// of the choices; elsewhere a bc_ui select sits under the row's text on a
/// phone, beside it where there's room.
///
/// Not a pull-down `UIMenu`: `native_liquid_glass` supports one menu
/// trigger per screen, and these screens have several.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.native,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.description,
    this.leading,
    this.compact = false,
  });

  final bool native;
  final String title;
  final String? description;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  /// The row's icon, before the title.
  final Widget? icon;

  /// Shown before the current choice, e.g. the app's badge.
  final Widget? leading;

  /// Off iPhone, keeps the select beside the title even on a phone: for
  /// short rows with short choices, like an item's place.
  final bool compact;

  static bool _isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  Future<void> _choose(BuildContext context) async {
    final keys = options.keys.toList();
    final id = await LiquidGlassAlert.show(
      context: context,
      // UIKit's action sheet shows no checkmark, so the title says which
      // choice is set.
      title: '$title: ${options[value]}',
      message: description,
      style: LiquidGlassAlertStyle.actionSheet,
      actions: [
        for (final (i, key) in keys.indexed)
          LiquidGlassAlertAction(id: '$i', title: options[key]!),
        const LiquidGlassAlertAction(
          id: 'cancel',
          title: 'Cancel',
          isCancel: true,
        ),
      ],
    );
    final index = int.tryParse(id ?? '');
    if (index != null) onChanged(keys[index]);
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    if (!native) {
      final narrow = _isNarrow(context) && !compact;
      final picker = SizedBox(
        width: narrow ? double.infinity : (compact ? 170 : 190),
        child: BCSelect<T>(
          listLabel: title,
          value: value,
          items: [
            for (final MapEntry(:key, value: text) in options.entries)
              BCSelectItem(value: key, label: text),
          ],
          onValueChange: onChanged,
        ),
      );
      if (!narrow) {
        return BCListGroupItem(
          prefix: icon,
          title: title,
          description: description,
          suffix: picker,
        );
      }
      return BCListGroupItem(
        prefix: icon,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            BCText(title),
            if (description case final description?)
              BCText(
                description,
                type: BCTextType.bodySm,
                color: BCTextColor.muted,
              ),
            const SizedBox(height: BCSpacing.xs),
            picker,
          ],
        ),
      );
    }
    return Semantics(
      button: true,
      label: '$title, ${options[value]}',
      excludeSemantics: true,
      child: BCListGroupItem(
        prefix: icon,
        title: title,
        description: description,
        onPressed: () => _choose(context),
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            ?leading,
            BCText(options[value]!, color: BCTextColor.muted),
            Icon(LucideIcons.chevronsUpDown, size: 15, color: bc.muted),
          ],
        ),
      ),
    );
  }
}
