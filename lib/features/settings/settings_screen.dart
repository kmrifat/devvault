import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../data/app_settings.dart';
import '../../data/providers.dart';
import '../../data/sync_setup.dart';
import '../../data/vault_session.dart';
import '../../services/biometric_key_store.dart';
import '../../services/folder_revealer.dart';
import '../../shared/ui.dart';
import 'change_password_dialog.dart';
import 'new_recovery_kit_dialog.dart';
import 'settings_layout.dart';

/// Settings: appearance, when the vault locks and how long copied secrets
/// stay on the clipboard, the master password, and facts about this vault.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static String autoLockLabel(Duration? after) => switch (after) {
    null => 'Never',
    Duration(inHours: final h) when h >= 1 => h == 1 ? '1 hour' : '$h hours',
    Duration(inMinutes: 1) => '1 minute',
    Duration(:final inMinutes) => '$inMinutes minutes',
  };

  static String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Match system',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bc = context.bcTheme;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final session = ref.watch(vaultSessionProvider);
    final vault = session is Unlocked ? session.vault : null;
    final revealer = ref.watch(folderRevealerProvider);
    final syncSetup = ref.watch(syncSetupProvider);

    return Scaffold(
      backgroundColor: bc.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: SettingsLayout.padding(context),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BCText('Settings', type: BCTextType.h2),
                  const _Section('General'),
                  BCListGroup(
                    children: [
                      _pickerItem(
                        context,
                        prefix: const Icon(LucideIcons.sunMoon),
                        title: 'Appearance',
                        picker: _Picker<ThemeMode>(
                          label: 'Appearance',
                          value: settings.themeMode,
                          options: {
                            for (final mode in ThemeMode.values)
                              mode: _themeLabel(mode),
                          },
                          onChanged: notifier.setThemeMode,
                        ),
                      ),
                      BCListGroupItem(
                        prefix: const Icon(LucideIcons.bellRing),
                        title: 'Expiry reminders',
                        description:
                            'At most two per item, at 09:00: when it enters '
                            'its last 30 days, and on the day it expires.',
                        suffix: BCSwitch(
                          isSelected: settings.expiryReminders,
                          onSelectedChange: notifier.setExpiryReminders,
                        ),
                      ),
                    ],
                  ),
                  const _Section('Security'),
                  BCListGroup(
                    children: [
                      if (vault != null) ..._BiometricRow.rows(context, ref),
                      _pickerItem(
                        context,
                        prefix: const Icon(LucideIcons.timer),
                        title: 'Lock after',
                        description: ref.watch(lockInBackgroundProvider)
                            ? 'Without input, and as soon as DevVault goes to '
                                  'the background.'
                            : 'Without input. '
                                  '${defaultTargetPlatform == TargetPlatform.macOS ? '⌘L' : 'Ctrl+L'} '
                                  'locks right away.',
                        picker: _Picker<Duration?>(
                          label: 'Lock after',
                          value: settings.autoLockAfter,
                          options: {
                            for (final after in AppSettings.autoLockChoices)
                              after: autoLockLabel(after),
                          },
                          onChanged: notifier.setAutoLock,
                        ),
                      ),
                      _pickerItem(
                        context,
                        prefix: const Icon(LucideIcons.clipboardX),
                        title: 'Clear copied secrets after',
                        description: 'Only if nothing else was copied since.',
                        picker: _Picker<Duration>(
                          label: 'Clear copied secrets after',
                          value: settings.clipboardClearAfter,
                          options: {
                            for (final after in AppSettings.clipboardChoices)
                              after: '${after.inSeconds} seconds',
                          },
                          onChanged: notifier.setClipboardClear,
                        ),
                      ),
                      BCListGroupItem(
                        prefix: const Icon(LucideIcons.keyRound),
                        title: 'Master password',
                        description:
                            'Changing it rewrites only vault.json; items '
                            'stay as they are.',
                        suffix: BCButton(
                          size: BCButtonSize.sm,
                          variant: BCButtonVariant.secondary,
                          isDisabled: vault == null,
                          onPressed: () => showChangePasswordDialog(context),
                          child: const Text('Change…'),
                        ),
                      ),
                      BCListGroupItem(
                        prefix: const Icon(LucideIcons.lifeBuoy),
                        title: 'Recovery kit',
                        description:
                            'Lost it? Make a new key as a PDF, printout or '
                            'text file. The old key stops working.',
                        suffix: BCButton(
                          size: BCButtonSize.sm,
                          variant: BCButtonVariant.secondary,
                          isDisabled: vault == null,
                          onPressed: () => showNewRecoveryKitDialog(context),
                          child: const Text('New kit…'),
                        ),
                      ),
                    ],
                  ),
                  const _Section('Sync'),
                  BCListGroup(
                    children: [
                      BCListGroupItem(
                        prefix: const Icon(LucideIcons.cloud),
                        title: 'Sync storage',
                        description: switch (syncSetup) {
                          null =>
                            'Not set up: this vault is on this device only.',
                          final s =>
                            '${s.settings.provider.label} · '
                                '${s.settings.bucket}',
                        },
                        suffix: Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: bc.muted,
                        ),
                        onPressed: () => context.go(Routes.settingsSync),
                      ),
                      if (syncSetup != null)
                        BCListGroupItem(
                          prefix: const Icon(LucideIcons.qrCode),
                          title: 'Pair a device',
                          description:
                              'Show a QR code another device scans to join '
                              'this vault. It still needs the master password.',
                          suffix: Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: bc.muted,
                          ),
                          onPressed: () => context.push(Routes.pair),
                        ),
                    ],
                  ),
                  if (vault != null) ...[
                    const _Section('This vault'),
                    _VaultFacts(vault: vault, revealer: revealer),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Unlock with Face ID" (SPEC §9.1): shown only where the device offers
/// biometrics.
abstract final class _BiometricRow {
  static List<Widget> rows(BuildContext context, WidgetRef ref) {
    final status = ref.watch(biometricUnlockProvider).value;
    final biometry = status?.biometry;
    if (biometry == null) return const [];
    final session = ref.read(vaultSessionProvider.notifier);

    Future<void> toggle(bool on) async {
      try {
        if (!on) return await session.disableBiometricUnlock();
        await session.enableBiometricUnlock(
          reason: 'Turn on unlocking DevVault with ${biometry.label}',
        );
      } on BiometricKeyUnavailable {
        if (!context.mounted) return;
        BCToast.show(
          context,
          BCToastData(
            title: "Couldn't turn on ${biometry.label}",
            description:
                'This device refused to keep the key. Use the '
                'master password to unlock.',
            variant: BCToastVariant.danger,
          ),
        );
      }
    }

    return [
      BCListGroupItem(
        prefix: Icon(
          biometry == Biometry.faceId
              ? LucideIcons.scanFace
              : LucideIcons.fingerprint,
        ),
        title: 'Unlock with ${biometry.label}',
        description:
            'The vault key stays on this device, behind ${biometry.label}. '
            'Changing the master password turns this off.',
        suffix: BCSwitch(isSelected: status!.enabled, onSelectedChange: toggle),
      ),
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 28, 6, 8),
      child: BCText(
        title,
        type: BCTextType.bodySm,
        weight: BCTextWeight.medium,
        color: BCTextColor.muted,
      ),
    );
  }
}

/// A settings row with a select: beside the text where there's room,
/// under it on a phone, where a 190-wide select would squeeze the title.
BCListGroupItem _pickerItem(
  BuildContext context, {
  required Widget prefix,
  required String title,
  String? description,
  required Widget picker,
}) {
  if (!SettingsLayout.isNarrow(context)) {
    return BCListGroupItem(
      prefix: prefix,
      title: title,
      description: description,
      suffix: picker,
    );
  }
  return BCListGroupItem(
    prefix: prefix,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: [
        BCText(title),
        if (description != null)
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

/// A compact select for a settings row (full width on a phone).
class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SettingsLayout.isNarrow(context) ? double.infinity : 190,
      child: BCSelect<T>(
        listLabel: label,
        value: value,
        items: [
          for (final MapEntry(:key, value: text) in options.entries)
            BCSelectItem(value: key, label: text),
        ],
        onValueChange: onChanged,
      ),
    );
  }
}

/// The vault's id, where it lives on disk and how it's encrypted, read
/// from `vault.json`.
class _VaultFacts extends ConsumerWidget {
  const _VaultFacts({required this.vault, required this.revealer});

  final Vault vault;
  final FolderRevealer revealer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bc = context.bcTheme;
    final kdf = vault.header.kdf;
    final folder = vault.store.root;
    // Shown inside the app's data folder; Show opens the real place.
    final supportDir = ref.watch(appSupportDirProvider).path;
    final shownPath = folder.path.startsWith(supportDir)
        ? 'App data${folder.path.substring(supportDir.length)}'
        : folder.path;
    TextStyle mono() =>
        AppText.mono(context, fontSize: BCTypography.sizeXs, color: bc.muted);

    return BCListGroup(
      children: [
        BCListGroupItem(
          prefix: const Icon(LucideIcons.fingerprint),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              const BCText('Vault ID'),
              MonoText(vault.vaultId, style: mono()),
            ],
          ),
          suffix: BCButton(
            size: BCButtonSize.sm,
            variant: BCButtonVariant.ghost,
            isIconOnly: true,
            onPressed: () async {
              await ref
                  .read(clipboardGuardProvider)
                  .clipboard
                  .write(vault.vaultId);
              if (!context.mounted) return;
              BCToast.show(
                context,
                const BCToastData(
                  title: 'Vault ID copied',
                  variant: BCToastVariant.success,
                ),
              );
            },
            child: const Icon(
              LucideIcons.copy,
              size: 16,
              semanticLabel: 'Copy vault ID',
            ),
          ),
        ),
        BCListGroupItem(
          prefix: const Icon(LucideIcons.folder),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              const BCText('Folder'),
              MonoText(shownPath, middleEllipsis: true, style: mono()),
            ],
          ),
          suffix: revealer.isSupported
              ? BCButton(
                  size: BCButtonSize.sm,
                  variant: BCButtonVariant.secondary,
                  onPressed: () => revealer.reveal(folder),
                  child: const Text('Show'),
                )
              : null,
        ),
        BCListGroupItem(
          prefix: const Icon(LucideIcons.shieldCheck),
          title: 'Encryption',
          description:
              'XChaCha20-Poly1305 · Argon2id ${kdf.memLimit ~/ (1024 * 1024)} '
              'MiB, ${kdf.opsLimit} ${kdf.opsLimit == 1 ? 'pass' : 'passes'} · '
              'format v${Envelope.formatVersion}',
        ),
      ],
    );
  }
}
