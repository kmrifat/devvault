import 'package:intl/intl.dart';

import '../../data/join_vault.dart' show RemoteVault;
import '../../shared/desktop_ui.dart';
import '../settings/storage_form.dart' show StorageFormModel, StorageFormView;

/// Join a vault that already syncs to a bucket, on desktop, in the lock
/// screens' style (N01): a pairing code, or the storage typed in; then the
/// vault found there and its master password.
///
/// Only renders: [JoinVaultScreen] owns the form, the secrets and the
/// joining. The storage form itself is Settings' (`StorageFormView`).
class DesktopJoinVaultView extends StatelessWidget {
  const DesktopJoinVaultView({
    super.key,
    required this.form,
    required this.canScan,
    required this.pairText,
    required this.pairCode,
    required this.pairError,
    required this.found,
    required this.chosen,
    required this.password,
    required this.passwordError,
    required this.error,
    required this.busy,
    required this.onScan,
    required this.onUsePairing,
    required this.onFind,
    required this.onChoose,
    required this.onJoin,
    required this.onCreate,
  });

  final StorageFormModel form;

  /// Phones scan the pairing QR; desktops paste its text.
  final bool canScan;
  final TextEditingController pairText;
  final TextEditingController pairCode;
  final String? pairError;

  /// The vaults in the bucket, once looked for in the current storage.
  final List<RemoteVault>? found;
  final RemoteVault? chosen;
  final TextEditingController password;
  final String? passwordError;
  final String? error;
  final bool busy;

  final VoidCallback onScan;
  final VoidCallback onUsePairing;
  final VoidCallback onFind;
  final ValueChanged<String> onChoose;
  final VoidCallback onJoin;
  final VoidCallback onCreate;

  static const double _labelWidth = 104;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final found = this.found;
    final chosen = this.chosen;
    final pairError = this.pairError;
    final passwordError = this.passwordError;
    final error = this.error;
    final secondary = TextStyle(
      fontSize: DesktopMetrics.secondarySize + 1,
      color: colors.secondaryText,
    );
    final created = DateFormat.yMMMd();

    return DesktopLockWindow(
      title: 'Join your vault',
      message:
          'Open the vault you already use on another device, from the '
          'bucket it syncs to. You need the same storage keys and the '
          'master password.',
      footer: Row(
        children: [
          DesktopLink(
            label: 'Create a new vault instead',
            onPressed: busy ? null : onCreate,
          ),
          const Spacer(),
          DesktopButton(
            label: busy && chosen != null ? 'Joining…' : 'Join vault',
            kind: DesktopButtonKind.primary,
            size: DesktopButtonSize.large,
            onPressed: busy || chosen == null ? null : onJoin,
          ),
        ],
      ),
      children: [
        DesktopGroupBox(
          title: 'With a pairing code',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Text(
                'On your other device: Settings › Pair a device. It shows a '
                'QR code and an 8-character code that work for ten minutes.',
                style: secondary,
              ),
              DesktopForm(
                labelWidth: _labelWidth,
                children: [
                  if (canScan)
                    DesktopFormRow(
                      label: 'QR code',
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: DesktopButton(
                          label: pairText.text.isEmpty
                              ? 'Scan QR code'
                              : 'QR code scanned',
                          size: DesktopButtonSize.large,
                          onPressed: busy ? null : onScan,
                        ),
                      ),
                    )
                  else
                    DesktopFormRow(
                      label: 'Pairing text',
                      note: 'From “Copy pairing text” on the other device',
                      child: Semantics(
                        label: 'Pairing text',
                        child: DesktopTextField(
                          key: const ValueKey('pairing-text'),
                          controller: pairText,
                          placeholder: 'devvault-pair:1:…',
                          mono: true,
                        ),
                      ),
                    ),
                  DesktopFormRow(
                    label: 'Code',
                    child: Semantics(
                      label: 'Pairing code',
                      child: DesktopTextField(
                        key: const ValueKey('pairing-code'),
                        controller: pairCode,
                        placeholder: 'ABCD-EFGH',
                        mono: true,
                        onSubmitted: (_) => onUsePairing(),
                      ),
                    ),
                  ),
                  if (pairError != null)
                    DesktopFieldMessage(pairError, indent: _labelWidth),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: DesktopButton(
                  label: 'Use pairing code',
                  size: DesktopButtonSize.large,
                  onPressed: busy ? null : onUsePairing,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Or enter the storage yourself',
          style: TextStyle(
            fontSize: DesktopMetrics.secondarySize,
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
        // Settings' storage form; it moves to the desktop controls with
        // Settings (N07b).
        StorageFormView(model: form),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: DesktopButton(
            label: 'Find vaults',
            icon: DesktopSymbol.search,
            size: DesktopButtonSize.large,
            onPressed: busy ? null : onFind,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  'Couldn’t continue',
                  style: TextStyle(
                    fontSize: DesktopMetrics.bodySize,
                    fontWeight: FontWeight.w600,
                    color: colors.danger,
                  ),
                ),
                Text(error, style: secondary),
              ],
            ),
          ),
        ],
        if (found != null) ...[
          const SizedBox(height: 20),
          DesktopGroupBox(
            title: 'Vaults in this bucket',
            child: found.isEmpty
                ? Text(
                    'No vault here yet. Check the folder, or set up sync from '
                    'the device that has the vault.',
                    style: secondary,
                  )
                : DesktopForm(
                    labelWidth: _labelWidth,
                    children: [
                      DesktopFormRow(
                        label: 'Vault',
                        note: chosen == null
                            ? null
                            : 'Created ${created.format(chosen.createdAt)}'
                                  ' · ${chosen.id}',
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: DesktopPopup<String>(
                            value: chosen?.id,
                            placeholder: 'Choose a vault',
                            onChanged: busy ? null : onChoose,
                            choices: [
                              for (final v in found)
                                DesktopChoice(
                                  v.id,
                                  'Vault ${v.id.substring(0, 8)}',
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (chosen != null)
                        DesktopFormRow(
                          label: 'Master password',
                          child: Semantics(
                            label: 'Master password',
                            child: DesktopTextField(
                              key: const ValueKey('join-password'),
                              controller: password,
                              obscureText: true,
                              autofocus: true,
                              enabled: !busy,
                              onSubmitted: (_) => onJoin(),
                            ),
                          ),
                        ),
                      if (passwordError != null)
                        DesktopFieldMessage(passwordError, indent: _labelWidth),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

extension on RemoteVault {
  /// When the vault was made, as `vault.json` says, in local time.
  DateTime get createdAt => header.createdAt.toLocal();
}
