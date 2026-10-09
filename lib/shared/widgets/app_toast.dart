import 'package:bc_ui/bc_ui.dart';
import 'package:flutter/widgets.dart';

import '../desktop/desktop_theme.dart';
import '../desktop/desktop_toast.dart';

/// Shows [data] as a toast, the way the platform does: on desktop the
/// kit's own ([showDesktopToast]: a banner on macOS, an `InfoBar` on
/// Windows, a snackbar on Linux), on phones bc_ui's. Never put a secret
/// in it.
void showAppToast(BuildContext context, BCToastData data) {
  if (DesktopTheme.maybeOf(context) == null) {
    BCToast.show(context, data);
    return;
  }
  showDesktopToast(
    context,
    title: data.title,
    message: data.description,
    kind: switch (data.variant) {
      BCToastVariant.success => DesktopToastKind.success,
      BCToastVariant.danger => DesktopToastKind.danger,
      _ => DesktopToastKind.info,
    },
    actionLabel: data.actionLabel,
    onAction: data.onAction,
    duration: data.duration,
  );
}
