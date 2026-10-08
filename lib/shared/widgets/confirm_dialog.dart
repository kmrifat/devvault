import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';

import '../desktop/desktop_button.dart';
import '../desktop/desktop_sheet.dart';
import '../desktop/desktop_theme.dart';

/// Asks the user to confirm an action. Resolves to `true` only when the
/// confirm button is pressed; dismissing or cancelling gives `false`.
///
/// On desktop it is a sheet drawn by the OS's kit; on phones, a bc_ui
/// dialog.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  if (DesktopTheme.maybeOf(context) != null) {
    final confirmed = await showDesktopSheet<bool>(
      context,
      builder: (context) => DesktopSheet(
        title: title,
        width: 420,
        actions: [
          DesktopButton(
            label: cancelLabel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          DesktopButton(
            label: confirmLabel,
            kind: destructive
                ? DesktopButtonKind.destructive
                : DesktopButtonKind.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        child: Text(message),
      ),
    );
    return confirmed ?? false;
  }
  final confirmed = await BCDialog.show<bool>(
    context,
    builder: (context) => BCDialogContent(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BCDialogTitle(title),
          const SizedBox(height: BCSpacing.xs),
          BCDialogDescription(message),
          const SizedBox(height: BCSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: BCSpacing.sm,
            children: [
              BCButton(
                variant: BCButtonVariant.secondary,
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(cancelLabel),
              ),
              BCButton(
                variant: destructive
                    ? BCButtonVariant.danger
                    : BCButtonVariant.primary,
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return confirmed ?? false;
}
