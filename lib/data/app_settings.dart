import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;

/// This device's preferences. Nothing secret: they live in plain JSON at
/// `<app support>/settings.json`, outside any vault, and aren't synced.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.autoLockAfter = defaultAutoLock,
    this.clipboardClearAfter = defaultClipboardClear,
    this.expiryReminders = true,
    this.agentsEnabled = false,
    this.agentMetadataWithoutAsking = true,
  });

  static const defaultAutoLock = Duration(minutes: 5);
  static const defaultClipboardClear = Duration(seconds: 30);

  /// The choices the settings screen offers; anything else read from the
  /// file falls back to the default.
  static const autoLockChoices = <Duration?>[
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    null,
  ];
  static const clipboardChoices = [
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 90),
  ];

  final ThemeMode themeMode;

  /// Idle time before the vault locks itself; null never locks on idle.
  final Duration? autoLockAfter;

  /// How long a copied secret stays on the clipboard.
  final Duration clipboardClearAfter;

  /// Whether expiry reminders are scheduled (P4-03): at most two per item.
  final bool expiryReminders;

  /// Whether AI agents may connect through `devvault-mcp` (P5). Off until
  /// the user turns it on; while off there is no socket.
  final bool agentsEnabled;

  /// Whether a paired agent may list and read item metadata without
  /// asking each time. Secret values always ask.
  final bool agentMetadataWithoutAsking;

  AppSettings copyWith({
    ThemeMode? themeMode,
    Duration? Function()? autoLockAfter,
    Duration? clipboardClearAfter,
    bool? expiryReminders,
    bool? agentsEnabled,
    bool? agentMetadataWithoutAsking,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    autoLockAfter: autoLockAfter == null ? this.autoLockAfter : autoLockAfter(),
    clipboardClearAfter: clipboardClearAfter ?? this.clipboardClearAfter,
    expiryReminders: expiryReminders ?? this.expiryReminders,
    agentsEnabled: agentsEnabled ?? this.agentsEnabled,
    agentMetadataWithoutAsking:
        agentMetadataWithoutAsking ?? this.agentMetadataWithoutAsking,
  );

  Map<String, Object?> toJson() => {
    'theme': themeMode.name,
    'auto_lock_seconds': autoLockAfter?.inSeconds,
    'clipboard_clear_seconds': clipboardClearAfter.inSeconds,
    'expiry_reminders': expiryReminders,
    'agents_enabled': agentsEnabled,
    'agent_metadata_without_asking': agentMetadataWithoutAsking,
  };

  /// Reads what it recognises and keeps the default for the rest, so a
  /// hand-edited or older file never stops the app from starting.
  factory AppSettings.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const AppSettings();
    final theme = ThemeMode.values
        .where((m) => m.name == json['theme'])
        .firstOrNull;
    Duration? seconds(Object? value) =>
        value is int ? Duration(seconds: value) : null;
    final autoLock = json.containsKey('auto_lock_seconds')
        ? seconds(json['auto_lock_seconds'])
        : defaultAutoLock;
    final clipboard = seconds(json['clipboard_clear_seconds']);
    return AppSettings(
      themeMode: theme ?? ThemeMode.system,
      autoLockAfter: autoLockChoices.contains(autoLock)
          ? autoLock
          : defaultAutoLock,
      clipboardClearAfter: clipboardChoices.contains(clipboard)
          ? clipboard!
          : defaultClipboardClear,
      expiryReminders: json['expiry_reminders'] != false,
      agentsEnabled: json['agents_enabled'] == true,
      agentMetadataWithoutAsking:
          json['agent_metadata_without_asking'] != false,
    );
  }

  static File fileIn(Directory supportDir) =>
      File('${supportDir.path}/settings.json');

  /// The saved settings, or the defaults when there are none or the file
  /// can't be read.
  static AppSettings load(Directory supportDir) {
    try {
      final file = fileIn(supportDir);
      if (!file.existsSync()) return const AppSettings();
      return AppSettings.fromJson(json.decode(file.readAsStringSync()));
    } on Object {
      return const AppSettings();
    }
  }

  /// Writes the settings atomically (temp file, then rename).
  Future<void> save(Directory supportDir) async {
    final file = fileIn(supportDir);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
      flush: true,
    );
    await temp.rename(file.path);
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.autoLockAfter == autoLockAfter &&
      other.clipboardClearAfter == clipboardClearAfter &&
      other.expiryReminders == expiryReminders &&
      other.agentsEnabled == agentsEnabled &&
      other.agentMetadataWithoutAsking == agentMetadataWithoutAsking;

  @override
  int get hashCode => Object.hash(
    themeMode,
    autoLockAfter,
    clipboardClearAfter,
    expiryReminders,
    agentsEnabled,
    agentMetadataWithoutAsking,
  );
}
