import 'package:flutter/foundation.dart';

/// System screens DevVault opens on purpose: the file picker, the share
/// sheet, the print dialog. On a phone they can send DevVault to the
/// background, which would otherwise lock the vault mid-task (P3-06).
abstract final class ExternalUi {
  /// How many are open right now.
  static final ValueNotifier<int> open = ValueNotifier(0);

  static bool get isOpen => open.value > 0;

  /// Runs [show], counting it as open until it returns.
  static Future<T> run<T>(Future<T> Function() show) async {
    open.value++;
    try {
      return await show();
    } finally {
      open.value--;
    }
  }
}
