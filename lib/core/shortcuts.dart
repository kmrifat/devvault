import 'package:flutter/foundation.dart';

/// How a keyboard shortcut is written on this platform: `⌘R` on macOS,
/// `Ctrl+R` on Windows and Linux.
String shortcutLabel(String key) =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘$key' : 'Ctrl+$key';
