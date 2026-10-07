import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../services/clipboard_guard.dart';
import 'app_settings.dart';
import '../services/file_export.dart';
import '../services/file_saver.dart';
import '../services/folder_revealer.dart';

// Every service the app depends on, in one place. Values that need I/O are
// loaded in main() before the first frame and handed in with overrides, so
// providers stay synchronous. Tests override the same providers with fakes
// (see test/test_overrides.dart).

/// The current time. Overridden with a fixed clock in tests, so expiry
/// rules and notification plans are deterministic.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The app support folder: vaults, device id and sync state live here.
final appSupportDirProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// This device's id, stamped on every record it writes.
final deviceIdProvider = Provider<String>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// libsodium, loaded once in main(). Tests load it too: the native library
/// is compiled for the host by the `sodium` package's build hooks.
final cryptoProvider = Provider<VaultCrypto>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Where vaults live: `<app support>/vaults/<vault_id>/`.
final vaultsDirProvider = Provider<Directory>(
  (ref) => Directory('${ref.watch(appSupportDirProvider).path}/vaults'),
);

/// Argon2id cost for new vaults and password changes (ADR-0003). Tests
/// lower it to keep runs fast.
final kdfOpsLimitProvider = Provider<int>((ref) => KdfParams.defaultOpsLimit);
final kdfMemLimitProvider = Provider<int>((ref) => KdfParams.defaultMemLimit);

/// Copies secrets and clears them again (default after 30 seconds, and on
/// lock).
final clipboardGuardProvider = Provider<ClipboardGuard>((ref) {
  final guard = ClipboardGuard(
    clearAfter: ref.read(settingsProvider).clipboardClearAfter,
  );
  // Follows the setting without dropping a clear that's already pending.
  ref.listen(
    settingsProvider.select((s) => s.clipboardClearAfter),
    (_, after) => guard.clearAfter = after,
  );
  ref.onDispose(guard.dispose);
  return guard;
});

/// Save dialogs (recovery kit, exported files).
final fileSaverProvider = Provider<FileSaver>((ref) => const SystemFileSaver());

/// Writes attachments back out byte for byte, through [fileSaverProvider].
final fileExportProvider = Provider<FileExport>(
  (ref) => FileExport(ref.watch(fileSaverProvider)),
);

/// The settings saved on this device, read in main() before the first
/// frame. Tests start from the defaults.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => const AppSettings(),
);

/// This device's preferences. Every change is saved to `settings.json`.
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  /// Saves run one after another, each writing the latest state, so quick
  /// changes can't interleave in the temp file.
  Future<void> _saving = Future.value();

  void update(AppSettings next) {
    if (next == state) return;
    state = next;
    final dir = ref.read(appSupportDirProvider);
    // Best effort: a failed write only means the old value returns next
    // launch, never a broken vault.
    _saving = _saving.then((_) => state.save(dir)).catchError((_) {});
  }

  void setThemeMode(ThemeMode mode) => update(state.copyWith(themeMode: mode));

  void setAutoLock(Duration? after) =>
      update(state.copyWith(autoLockAfter: () => after));

  void setClipboardClear(Duration after) =>
      update(state.copyWith(clipboardClearAfter: after));
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// How long the vault stays open without input before it locks itself
/// (null: never), from [settingsProvider].
final autoLockProvider = Provider<Duration?>(
  (ref) => ref.watch(settingsProvider.select((s) => s.autoLockAfter)),
);

/// Shows folders in Finder / Explorer / the Linux file manager.
final folderRevealerProvider = Provider<FolderRevealer>(
  (ref) => const SystemFolderRevealer(),
);
