import 'package:vault_core/vault_core.dart' show VaultHeader;

import '../../services/biometric_key_store.dart' show Biometry;
import '../agents/agent_wait_banner.dart';
import '../../shared/desktop_ui.dart';

/// Design frame N00: the unlock screen on desktop. The app mark, the
/// password with its submit arrow (Return also unlocks), Touch ID or
/// Windows Hello when it's turned on, and the way to the recovery key.
///
/// Only renders: [UnlockScreen] owns the password, the attempts and the
/// biometric prompt, and hands their state in.
class DesktopUnlockView extends StatelessWidget {
  const DesktopUnlockView({
    super.key,
    required this.header,
    required this.password,
    required this.focusNode,
    required this.notice,
    required this.error,
    required this.busy,
    required this.wait,
    required this.biometry,
    required this.onChanged,
    required this.onUnlock,
    required this.onBiometrics,
    required this.onRecover,
  });

  /// What `vault.json` says, readable without the key.
  final VaultHeader? header;
  final TextEditingController password;
  final FocusNode focusNode;

  /// Why biometrics aren't offered any more.
  final String? notice;
  final String? error;
  final bool busy;

  /// How long until the next attempt is allowed.
  final Duration wait;

  /// Set when biometric unlock is turned on.
  final Biometry? biometry;

  final VoidCallback onChanged;
  final VoidCallback onUnlock;
  final ValueChanged<Biometry> onBiometrics;
  final VoidCallback onRecover;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final header = this.header;
    final notice = this.notice;
    final biometry = this.biometry;
    final waiting = wait > Duration.zero;
    final canUnlock = !busy && !waiting && password.text.isNotEmpty;
    final secondary = TextStyle(
      fontSize: DesktopMetrics.secondarySize + 1,
      color: colors.secondaryText,
    );

    // Under the field: what went wrong, or that it's working.
    final status = switch ((error, busy)) {
      (_, true) => ('Unlocking…', colors.secondaryText),
      (final String error, _) => (error, colors.danger),
      _ => null,
    };

    return DesktopLockWindow(
      centred: true,
      title: 'Unlock your vault',
      footnote: header == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                const DesktopIcon(DesktopSymbol.encrypted, size: 12),
                Text(
                  'Argon2id · ${header.kdf.memLimit ~/ (1024 * 1024)} MiB · '
                  '${header.kdf.opsLimit} '
                  '${header.kdf.opsLimit == 1 ? 'pass' : 'passes'} · '
                  'your password never leaves this device',
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
      children: [
        if (header != null)
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Locked · '),
                TextSpan(
                  text: 'vault ${header.vaultId}',
                  style: AppText.mono(
                    context,
                    fontSize: DesktopMetrics.secondarySize,
                  ).copyWith(color: colors.secondaryText),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondary,
          ),
        const SizedBox(height: 28),
        const AgentWaitBanner(),
        if (notice != null) ...[
          Text(notice, textAlign: TextAlign.center, style: secondary),
          const SizedBox(height: 14),
        ],
        SizedBox(
          width: _fieldWidth,
          child: Semantics(
            label: 'Master password',
            child: DesktopTextField(
              controller: password,
              // Focused once it's known whether a biometric prompt comes
              // first.
              focusNode: focusNode,
              placeholder: 'Master password',
              obscureText: true,
              enabled: !busy && !waiting,
              onChanged: (_) => onChanged(),
              onSubmitted: (_) => onUnlock(),
              suffix: _SubmitArrow(onPressed: canUnlock ? onUnlock : null),
            ),
          ),
        ),
        // One line, kept even when empty so nothing below jumps.
        SizedBox(
          width: _fieldWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                status?.$1 ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: DesktopMetrics.secondarySize,
                  color: status?.$2 ?? colors.secondaryText,
                ),
              ),
            ),
          ),
        ),
        // After too many wrong passwords: the wait, under what went wrong.
        if (waiting && !busy)
          Text(
            'Try again in ${wait.inSeconds} s',
            style: TextStyle(
              fontSize: DesktopMetrics.secondarySize,
              color: colors.secondaryText,
            ),
          ),
        if (biometry != null) ...[
          const SizedBox(height: 4),
          DesktopButton(
            label: 'Unlock with ${biometry.label}',
            icon: biometry == Biometry.faceId
                ? DesktopSymbol.faceId
                : DesktopSymbol.fingerprint,
            size: DesktopButtonSize.large,
            onPressed: busy ? null : () => onBiometrics(biometry),
          ),
        ],
        const SizedBox(height: 28),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            Text('Forgot your password?', style: secondary),
            DesktopLink(label: 'Use your recovery key…', onPressed: onRecover),
          ],
        ),
      ],
    );
  }

  static const double _fieldWidth = 280;
}

/// The arrow inside the password field's trailing edge: the default
/// action, in the accent colour once there's something to send.
class _SubmitArrow extends StatelessWidget {
  const _SubmitArrow({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final onPressed = this.onPressed;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Unlock',
      onTap: onPressed,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: onPressed == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 24,
            child: Center(
              child: DesktopIcon(
                DesktopSymbol.submit,
                size: 18,
                color: onPressed == null ? colors.tertiaryText : colors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
