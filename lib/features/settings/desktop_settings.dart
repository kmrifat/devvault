// Desktop settings still use bc_ui's toasts: the desktop layer has none
// yet, and the app's toast overlay is bc_ui's.
import 'package:bc_ui/bc_ui.dart' show BCToastData, BCToastVariant;

import '../../shared/widgets/app_toast.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/app_settings.dart';
import '../../data/providers.dart';
import '../../data/vault_session.dart';
import '../../services/biometric_key_store.dart';
import '../../shared/desktop_ui.dart';
import 'change_password_dialog.dart';
import 'desktop_agents_pane.dart';
import 'new_recovery_kit_dialog.dart';
import 'settings_layout.dart';
import 'settings_screen.dart' show SettingsScreen;
import 'sync_settings_screen.dart';

/// Settings on desktop (design frames N07c, N07, N07b, N07d): icon tabs
/// along the top (General, Security, Sync, AI Agents), each a link to its path, and the
/// pane's group boxes below.
///
/// The design draws Settings as its own window (⌘,); until it has one, it
/// is this page in the main window's content area.
class DesktopSettingsPage extends StatelessWidget {
  const DesktopSettingsPage({super.key, required this.pane});

  final SettingsPane pane;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsTabs(selected: pane),
        Expanded(
          child: ColoredBox(
            color: colors.groupBox,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: DesktopMetrics.settingsWidth,
                  ),
                  child: switch (pane) {
                    SettingsPane.general => const _GeneralPane(),
                    SettingsPane.security => const _SecurityPane(),
                    SettingsPane.sync => const SyncSettingsScreen(),
                    SettingsPane.agents => const DesktopAgentsPane(),
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
    // Body text, under the shell's Material (which sets its own).
    return DefaultTextStyle.merge(
      style: TextStyle(fontSize: DesktopMetrics.bodySize, color: colors.text),
      child: page,
    );
  }
}

/// The tab strip: an icon over a label per pane, the current one tinted.
class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs({required this.selected});

  final SettingsPane selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(bottom: BorderSide(color: colors.separator, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 4,
          children: [
            for (final pane in SettingsPane.values)
              _SettingsTab(
                pane: pane,
                selected: pane == selected,
                onTap: () => context.go(pane.route),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({
    required this.pane,
    required this.selected,
    required this.onTap,
  });

  final SettingsPane pane;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final selected = widget.selected;
    final ink = selected ? colors.accentIcon : colors.secondaryText;
    final symbol = switch (widget.pane) {
      SettingsPane.general => DesktopSymbol.settings,
      SettingsPane.security => DesktopSymbol.lock,
      SettingsPane.sync => DesktopSymbol.synced,
      SettingsPane.agents => DesktopSymbol.agent,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: widget.pane.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: DesktopMetrics.settingsTabWidth,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? colors.toolbarField
                  : _hovered
                  ? colors.zebra
                  : null,
              borderRadius: const BorderRadius.all(
                Radius.circular(DesktopMetrics.menuRadius),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                DesktopIcon(symbol, size: 18, color: ink),
                Text(
                  widget.pane.label,
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A group box of settings rows, with a line between rows.
class DesktopSettingsBox extends StatelessWidget {
  const DesktopSettingsBox({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.groupBoxInner,
        border: Border.all(color: colors.groupBoxStroke, width: 0.5),
        borderRadius: const BorderRadius.all(
          Radius.circular(DesktopMetrics.menuRadius + 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              SizedBox(
                height: 0.5,
                child: ColoredBox(color: colors.innerSeparator),
              ),
            child,
          ],
        ],
      ),
    );
  }
}

/// One settings row: a title and a line of description, with the control
/// at the trailing edge. [leading] is an optional icon before the text;
/// [details] are more lines under the description.
///
/// With [onTap] the whole row is the control's target and reads as one
/// with it (a switch row): a bigger target than the switch alone.
class DesktopSettingsRow extends StatelessWidget {
  const DesktopSettingsRow({
    super.key,
    required this.title,
    this.description,
    this.details = const [],
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? description;
  final List<String> details;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final secondary = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        spacing: 12,
        children: [
          ?leading,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 1,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: DesktopMetrics.bodySize,
                    color: colors.text,
                  ),
                ),
                for (final line in [?description, ...details])
                  Text(line, style: secondary),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return row;
    return MergeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

/// General (N07c): appearance and expiry reminders.
class _GeneralPane extends ConsumerWidget {
  const _GeneralPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return DesktopSettingsBox(
      children: [
        DesktopSettingsRow(
          title: 'Appearance',
          trailing: Semantics(
            label: 'Appearance',
            child: DesktopSegmented<ThemeMode>(
              value: settings.themeMode,
              choices: const [
                DesktopChoice(ThemeMode.system, 'System'),
                DesktopChoice(ThemeMode.light, 'Light'),
                DesktopChoice(ThemeMode.dark, 'Dark'),
              ],
              onChanged: notifier.setThemeMode,
            ),
          ),
        ),
        DesktopSettingsRow(
          title: 'Expiry reminders',
          onTap: () => notifier.setExpiryReminders(!settings.expiryReminders),
          description:
              'At most two per item, at 09:00: when it enters its last 30 '
              'days, and on the day it expires.',
          trailing: DesktopSwitch(
            value: settings.expiryReminders,
            onChanged: notifier.setExpiryReminders,
            semanticLabel: 'Expiry reminders',
          ),
        ),
      ],
    );
  }
}

/// Security (N07): when the vault locks, the clipboard, biometrics, the
/// master password, the recovery kit and the vault key, then facts about
/// this vault.
class _SecurityPane extends ConsumerWidget {
  const _SecurityPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final session = ref.watch(vaultSessionProvider);
    final vault = session is Unlocked ? session.vault : null;
    final lockKey = defaultTargetPlatform == TargetPlatform.macOS
        ? '⌘L'
        : 'Ctrl+L';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20,
      children: [
        DesktopSettingsBox(
          children: [
            DesktopSettingsRow(
              title: 'Lock after',
              description: ref.watch(lockInBackgroundProvider)
                  ? 'Without input, and as soon as DevVault goes to the '
                        'background.'
                  : 'Without input. $lockKey locks right away.',
              trailing: Semantics(
                label: 'Lock after',
                // By index: "Never" is null, which a pop-up can't report
                // as a choice.
                child: DesktopPopup<int>(
                  value: AppSettings.autoLockChoices.indexOf(
                    settings.autoLockAfter,
                  ),
                  choices: [
                    for (final (i, after)
                        in AppSettings.autoLockChoices.indexed)
                      DesktopChoice(i, SettingsScreen.autoLockLabel(after)),
                  ],
                  onChanged: (i) =>
                      notifier.setAutoLock(AppSettings.autoLockChoices[i]),
                ),
              ),
            ),
            DesktopSettingsRow(
              title: 'Clear copied secrets after',
              description: 'Only if nothing else was copied since.',
              trailing: Semantics(
                label: 'Clear copied secrets after',
                child: DesktopPopup<Duration>(
                  value: settings.clipboardClearAfter,
                  choices: [
                    for (final after in AppSettings.clipboardChoices)
                      DesktopChoice(after, '${after.inSeconds} seconds'),
                  ],
                  onChanged: notifier.setClipboardClear,
                ),
              ),
            ),
            if (vault != null) const _BiometricRow(),
          ],
        ),
        DesktopSettingsBox(
          children: [
            DesktopSettingsRow(
              title: 'Master password',
              description:
                  'Changing it rewrites only vault.json; items stay as they '
                  'are.',
              trailing: DesktopButton(
                label: 'Change…',
                onPressed: vault == null
                    ? null
                    : () => showChangePasswordDialog(context),
              ),
            ),
            DesktopSettingsRow(
              title: 'Recovery kit',
              description:
                  'Lost it? Make a new key as a PDF, printout or text file. '
                  'The old key stops working.',
              trailing: DesktopButton(
                label: 'New Kit…',
                onPressed: vault == null
                    ? null
                    : () => showNewRecoveryKitDialog(context),
              ),
            ),
            DesktopSettingsRow(
              title: 'Vault key',
              description:
                  'Suspect a leak? Re-encrypt everything under a new key, '
                  'with a new recovery key.',
              trailing: DesktopButton(
                label: 'Rotate…',
                onPressed: vault == null
                    ? null
                    : () => showRotateVaultKeyDialog(context),
              ),
            ),
          ],
        ),
        if (vault != null) _VaultFacts(vault: vault),
      ],
    );
  }
}

/// "Unlock with Touch ID" (SPEC §9.1): shown only where the device offers
/// biometrics.
class _BiometricRow extends ConsumerWidget {
  const _BiometricRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(biometricUnlockProvider).value;
    final biometry = status?.biometry;
    if (status == null || biometry == null) return const SizedBox.shrink();
    final session = ref.read(vaultSessionProvider.notifier);

    Future<void> toggle(bool on) async {
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
                'This device refused to keep the key. Use the master '
                'password to unlock.',
            variant: BCToastVariant.danger,
          ),
        );
      }
    }

    return DesktopSettingsRow(
      title: 'Unlock with ${biometry.label}',
      onTap: () => toggle(!status.enabled),
      description:
          'The vault key stays on this device, behind ${biometry.label}. '
          'Changing the master password turns this off.',
      trailing: DesktopSwitch(
        value: status.enabled,
        onChanged: toggle,
        semanticLabel: 'Unlock with ${biometry.label}',
      ),
    );
  }
}

/// The footer: the vault's id and folder, and how it's encrypted, read
/// from `vault.json`. Copy ID and Show in Finder act on them.
class _VaultFacts extends ConsumerWidget {
  const _VaultFacts({required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.desktopColors;
    final revealer = ref.watch(folderRevealerProvider);
    final kdf = vault.header.kdf;
    final folder = vault.store.root;
    // Shown inside the app's data folder; Show opens the real place.
    final supportDir = ref.watch(appSupportDirProvider).path;
    final shownPath = folder.path.startsWith(supportDir)
        ? 'App data${folder.path.substring(supportDir.length)}'
        : folder.path;
    final secondary = TextStyle(
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    final mono = AppText.mono(
      context,
      fontSize: DesktopMetrics.secondarySize,
      color: colors.secondaryText,
    );
    final showLabel = switch (context.desktopKit) {
      DesktopKit.macos => 'Show in Finder',
      DesktopKit.fluent => 'Show in Explorer',
      DesktopKit.yaru => 'Show in Files',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: DesktopIcon(DesktopSymbol.info, size: 12),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Text('Vault ID', style: secondary),
                    Text(vault.vaultId, style: mono),
                    Text('·', style: secondary),
                    Text(shownPath, style: mono),
                  ],
                ),
                Text(
                  'XChaCha20-Poly1305 · Argon2id '
                  '${kdf.memLimit ~/ (1024 * 1024)} MiB, ${kdf.opsLimit} '
                  '${kdf.opsLimit == 1 ? 'pass' : 'passes'} · '
                  'format v${Envelope.formatVersion}',
                  style: secondary,
                ),
              ],
            ),
          ),
          DesktopButton(
            label: 'Copy ID',
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
          ),
          if (revealer.isSupported)
            DesktopButton(
              label: showLabel,
              onPressed: () => revealer.reveal(folder),
            ),
        ],
      ),
    );
  }
}
