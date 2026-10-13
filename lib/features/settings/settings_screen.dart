import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart'
    show LiquidGlassToggle;
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../data/app_settings.dart';
import '../../data/providers.dart';
import '../../data/sync_controller.dart';
import '../../data/sync_setup.dart';
import '../../data/vault_session.dart';
import '../../services/biometric_key_store.dart';
import '../../services/folder_revealer.dart';
import '../../shared/desktop/desktop_theme.dart' show DesktopTheme;
import '../../shared/ui.dart';
import '../sync/sync_status_chip.dart';
import 'change_password_dialog.dart';
import 'desktop_settings.dart';
import 'new_recovery_kit_dialog.dart';
import 'settings_layout.dart';

/// Settings: appearance, when the vault locks and how long copied secrets
/// stay on the clipboard, the master password, and facts about this vault.
///
/// On desktop it is a page of tabs, opened on [pane] ([DesktopSettingsPage]);
/// phones show General and Security on this one page.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.pane = SettingsPane.general});

  final SettingsPane pane;

  static String autoLockLabel(Duration? after) => switch (after) {
    null => 'Never',
    Duration(inHours: final h) when h >= 1 => h == 1 ? '1 hour' : '$h hours',
    Duration(inMinutes: 1) => '1 minute',
    Duration(:final inMinutes) => '$inMinutes minutes',
  };

  /// What the "Unlock with Face ID" row says: what turning it on does, or
  /// why it can't be turned on right now.
  static String biometricNote(BiometricUnlock status, Biometry biometry) {
    final label = biometry.label;
    if (!status.storable) {
      return "This copy of DevVault isn't signed to keep a key behind "
          '$label. Unlock with the master password.';
    }
    return switch (status.unavailable) {
      null =>
        'The vault key stays on this device, behind $label. Changing the '
            'master password turns this off.',
      BiometryUnavailable.notEnrolled =>
        "$label isn't set up on this device. Set it up in the system "
            'settings first.',
      BiometryUnavailable.lockedOut =>
        '$label is locked after too many tries. Unlock the device with its '
            'password, then try again.',
      BiometryUnavailable.unavailable =>
        defaultTargetPlatform == TargetPlatform.macOS
            ? "$label isn't available right now. A MacBook's sensor is off "
                  'while its lid is closed.'
            : "$label isn't available right now.",
    };
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Match system',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (DesktopTheme.maybeOf(context) != null) {
      return DesktopSettingsPage(pane: pane);
    }
    return const _PhoneSettings();
  }
}

/// Settings on a phone (design frames I7, I8): the vault, General,
/// Security, Sync and this vault's facts, in bc_ui list groups. On iPhone
/// the switches are UIKit's, a choice opens UIKit's action sheet, and the
/// title is large until it scrolls under UIKit's bar, which holds Lock.
class _PhoneSettings extends ConsumerStatefulWidget {
  const _PhoneSettings();

  @override
  ConsumerState<_PhoneSettings> createState() => _PhoneSettingsState();
}

class _PhoneSettingsState extends ConsumerState<_PhoneSettings>
    with LargeTitleScroll {
  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final apps = context.appColors;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final session = ref.watch(vaultSessionProvider);
    final vault = session is Unlocked ? session.vault : null;
    final revealer = ref.watch(folderRevealerProvider);
    final syncSetup = ref.watch(syncSetupProvider);
    final native = ref.watch(nativeBarsProvider);
    void lock() => ref.read(vaultSessionProvider.notifier).lock();

    Widget toggle(bool value, ValueChanged<bool> onChanged) => native
        ? LiquidGlassToggle(
            value: value,
            onChanged: onChanged,
            color: bc.accent,
            height: 32,
          )
        : BCSwitch(isSelected: value, onSelectedChange: onChanged);

    Widget chevron() =>
        Icon(LucideIcons.chevronRight, size: 18, color: bc.muted);

    return Scaffold(
      backgroundColor: bc.background,
      extendBodyBehindAppBar: native,
      appBar: native
          ? NativePhoneHeader(
              title: titleInBar ? 'Settings' : '',
              actions: [
                if (vault != null)
                  NativeHeaderAction(
                    id: 'lock',
                    symbol: 'lock',
                    label: 'Lock',
                    onPressed: lock,
                  ),
              ],
            )
          : null,
      body: SingleChildScrollView(
        controller: titleScroll,
        padding: EdgeInsets.fromLTRB(
          0,
          native
              ? MediaQuery.paddingOf(context).top + NativePhoneHeader.barHeight
              : MediaQuery.paddingOf(context).top + 16,
          0,
          120,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (native)
              const PhoneLargeTitle('Settings')
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: BCText('Settings', type: BCTextType.h2),
                    ),
                    if (vault != null)
                      BCButton(
                        // 48 px: the touch-target minimum.
                        size: BCButtonSize.md,
                        variant: BCButtonVariant.secondary,
                        onPressed: lock,
                        startContent: const Icon(LucideIcons.lock, size: 15),
                        child: const Text('Lock'),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (session is Unlocked) ...[
                    const SizedBox(height: 16),
                    _VaultCard(count: session.index.all.length),
                  ],
                  const _Section('General'),
                  BCListGroup(
                    children: [
                      ChoiceRow<ThemeMode>(
                        native: native,
                        icon: _RowIcon(
                          LucideIcons.sunMoon,
                          bc.defaultColor,
                          bc.foreground,
                        ),
                        title: 'Appearance',
                        value: settings.themeMode,
                        options: {
                          for (final mode in ThemeMode.values)
                            mode: SettingsScreen._themeLabel(mode),
                        },
                        onChanged: notifier.setThemeMode,
                      ),
                      // The whole row toggles, and reads as one switch: a
                      // big enough target on a phone, and named.
                      MergeSemantics(
                        child: BCListGroupItem(
                          prefix: _RowIcon(
                            LucideIcons.bellRing,
                            bc.warningSoft,
                            bc.warningSoftForeground,
                          ),
                          title: 'Expiry reminders',
                          description:
                              'At most two per item, at 09:00: when it enters '
                              'its last 30 days, and on the day it expires.',
                          onPressed: () => notifier.setExpiryReminders(
                            !settings.expiryReminders,
                          ),
                          suffix: toggle(
                            settings.expiryReminders,
                            notifier.setExpiryReminders,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const _Section('Security'),
                  BCListGroup(
                    children: [
                      if (vault != null)
                        ..._BiometricRow.rows(context, ref, toggle: toggle),
                      ChoiceRow<Duration?>(
                        native: native,
                        icon: _RowIcon(
                          LucideIcons.timer,
                          bc.accentSoft,
                          bc.accentSoftForeground,
                        ),
                        title: 'Lock after',
                        description: ref.watch(lockInBackgroundProvider)
                            ? 'Without input, and as soon as DevVault goes to '
                                  'the background.'
                            : 'Without input.',
                        value: settings.autoLockAfter,
                        options: {
                          for (final after in AppSettings.autoLockChoices)
                            after: SettingsScreen.autoLockLabel(after),
                        },
                        onChanged: notifier.setAutoLock,
                      ),
                      ChoiceRow<Duration>(
                        native: native,
                        icon: _RowIcon(
                          LucideIcons.clipboardX,
                          bc.accentSoft,
                          bc.accentSoftForeground,
                        ),
                        title: 'Clear copied secrets after',
                        description: 'Only if nothing else was copied since.',
                        value: settings.clipboardClearAfter,
                        options: {
                          for (final after in AppSettings.clipboardChoices)
                            after: '${after.inSeconds} seconds',
                        },
                        onChanged: notifier.setClipboardClear,
                      ),
                      BCListGroupItem(
                        prefix: _RowIcon(
                          LucideIcons.keyRound,
                          bc.defaultColor,
                          bc.foreground,
                        ),
                        title: 'Master password',
                        description:
                            'Changing it rewrites only vault.json; items '
                            'stay as they are.',
                        suffix: chevron(),
                        isDisabled: vault == null,
                        onPressed: () => showChangePasswordDialog(context),
                      ),
                      BCListGroupItem(
                        prefix: _RowIcon(
                          LucideIcons.lifeBuoy,
                          bc.defaultColor,
                          bc.foreground,
                        ),
                        title: 'New recovery kit',
                        description:
                            'Lost it? Make a new key as a PDF, printout or '
                            'text file. The old key stops working.',
                        suffix: chevron(),
                        isDisabled: vault == null,
                        onPressed: () => showNewRecoveryKitDialog(context),
                      ),
                      BCListGroupItem(
                        prefix: _RowIcon(
                          LucideIcons.refreshCcwDot,
                          bc.defaultColor,
                          bc.foreground,
                        ),
                        title: 'Rotate vault key',
                        description:
                            'Suspect a leak? Everything is re-encrypted under '
                            'a new key, with a new recovery key.',
                        suffix: chevron(),
                        isDisabled: vault == null,
                        onPressed: () => showRotateVaultKeyDialog(context),
                      ),
                    ],
                  ),
                  const _Section('Sync'),
                  BCListGroup(
                    children: [
                      BCListGroupItem(
                        prefix: _RowIcon(
                          LucideIcons.cloud,
                          apps.tealSoft,
                          apps.teal,
                        ),
                        title: 'Sync storage',
                        description: switch (syncSetup) {
                          null =>
                            'Not set up: this vault is on this device only.',
                          final s =>
                            '${s.settings.provider.label} · '
                                '${s.settings.bucket}',
                        },
                        suffix: chevron(),
                        onPressed: () => context.go(Routes.settingsSync),
                      ),
                      if (syncSetup != null)
                        BCListGroupItem(
                          prefix: _RowIcon(
                            LucideIcons.qrCode,
                            apps.tealSoft,
                            apps.teal,
                          ),
                          title: 'Pair a device',
                          description:
                              'Show a QR code another device scans to join '
                              'this vault. It still needs the master password.',
                          suffix: chevron(),
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
          ],
        ),
      ),
    );
  }
}

/// The vault at the top of Settings (design frame I7): the app mark, how
/// many items it holds on this device, and the sync status.
class _VaultCard extends ConsumerWidget {
  const _VaultCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(syncControllerProvider) is! SyncOff;
    return BCCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        spacing: 14,
        children: [
          const AppMark(size: 48),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                const BCText('DevVault', weight: BCTextWeight.semibold),
                BCText(
                  '${count == 1 ? '1 item' : '$count items'} · this device',
                  type: BCTextType.bodySm,
                  color: BCTextColor.muted,
                ),
              ],
            ),
          ),
          if (syncing) const SyncStatusChip(),
        ],
      ),
    );
  }
}

/// A settings row's icon on a tinted tile.
class _RowIcon extends StatelessWidget {
  const _RowIcon(this.icon, this.background, this.foreground);

  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: BCShapes.continuous(BCRadius.lg),
      ),
      child: SizedBox.square(
        dimension: 32,
        child: Icon(icon, size: 17, color: foreground),
      ),
    );
  }
}

/// "Unlock with Face ID" (SPEC §9.1): shown only where the device has
/// biometrics, without its switch when they can't be used right now or this
/// build can't keep the key.
abstract final class _BiometricRow {
  static List<Widget> rows(
    BuildContext context,
    WidgetRef ref, {
    required Widget Function(bool value, ValueChanged<bool> onChanged) toggle,
  }) {
    final status = ref.watch(biometricUnlockProvider).value;
    final biometry = status?.biometry;
    if (biometry == null) return const [];
    final session = ref.read(vaultSessionProvider.notifier);

    Future<void> setBiometric(bool on) async {
      try {
        if (!on) return await session.disableBiometricUnlock();
        await session.enableBiometricUnlock(
          reason: 'Turn on unlocking DevVault with ${biometry.label}',
        );
      } on BiometricKeyUnavailable {
        if (!context.mounted) return;
        showAppToast(
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

    final bc = context.bcTheme;
    return [
      BCListGroupItem(
        prefix: _RowIcon(
          biometry == Biometry.faceId
              ? LucideIcons.scanFace
              : LucideIcons.fingerprint,
          bc.successSoft,
          bc.successSoftForeground,
        ),
        title: 'Unlock with ${biometry.label}',
        description: SettingsScreen.biometricNote(status!, biometry),
        suffix: status.storable && status.unavailable == null
            ? toggle(status.enabled, setBiometric)
            : null,
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
            size: SettingsLayout.buttonSize(context),
            variant: BCButtonVariant.ghost,
            isIconOnly: true,
            onPressed: () async {
              await ref
                  .read(clipboardGuardProvider)
                  .clipboard
                  .write(vault.vaultId);
              if (!context.mounted) return;
              showAppToast(
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
                  size: SettingsLayout.buttonSize(context),
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
