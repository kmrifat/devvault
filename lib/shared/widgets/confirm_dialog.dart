import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/material.dart';

/// Asks the user to confirm an action. Resolves to `true` only when the
/// confirm button is pressed; dismissing or cancelling gives `false`.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
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
