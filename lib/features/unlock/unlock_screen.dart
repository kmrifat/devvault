import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/routes.dart';
import '../../data/vault_session.dart';
import '../../services/biometric_key_store.dart';
import '../../shared/desktop_ui.dart' show DesktopTheme;
import '../../shared/ui.dart';
import 'desktop_unlock_view.dart';

/// Design frames N00 (desktop, [DesktopUnlockView]) and B1 (phone): unlock
/// with the master password, or with Face ID, Touch ID or a fingerprint
/// where it's turned on (SPEC §9.1). The biometric prompt opens by itself
/// once the app is in front; the password is always there as the way back
/// in.
///
/// Shows only facts it can read without the key: the vault id and the
/// Argon2id settings from `vault.json`. After repeated wrong passwords it
/// makes the user wait a little longer each time.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  /// Wrong attempts allowed before waiting starts.
  static const freeAttempts = 5;

  /// How long to wait after [failures] wrong attempts: 30 s after the
  /// fifth, doubling each time, at most 5 minutes.
  static Duration backoff(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final seconds = 30 * (1 << (failures - freeAttempts).clamp(0, 4));
    return Duration(seconds: seconds.clamp(0, 300));
  }

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _password = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _busy = false;
  int _failures = 0;
  Duration _wait = Duration.zero;
  Timer? _waitTimer;

  /// Why biometrics aren't offered any more, shown above the password.
  String? _notice;
  bool _prompted = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Prompt once the app is in front: a prompt raised while it locks in
    // the background would fail or pop up over another app.
    _lifecycle = AppLifecycleListener(onResume: _autoPrompt);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoPrompt());
  }

  @override
  void dispose() {
    _password
      ..clear()
      ..dispose();
    _waitTimer?.cancel();
    _lifecycle.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _autoPrompt() async {
    if (_prompted || !mounted) return;
    final status = await ref.read(biometricUnlockProvider.future);
    if (!mounted || _prompted) return;
    if (!status.enabled) return _focus.requestFocus();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _prompted = true;
    await _unlockWithBiometrics(status.biometry!);
  }

  Future<void> _unlockWithBiometrics(Biometry biometry) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(vaultSessionProvider.notifier)
          .unlockWithBiometrics(reason: 'Unlock your vault');
      // Unlocked: the router moves on. Cancelled: the password is here.
    } on BiometricKeyGone {
      setState(
        () => _notice =
            '${biometry.label} was turned off: the vault key changed, or '
            '${biometry.label} was set up again on this device. Unlock with '
            'your master password, then turn it back on in Settings.',
      );
    } on BiometricKeyUnavailable {
      setState(
        () => _notice =
            "${biometry.label} isn't available right now. Use your master "
            'password.',
      );
    } on Object {
      setState(() => _error = "Couldn't read the vault on this device");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() async {
    if (_busy || _wait > Duration.zero || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(vaultSessionProvider.notifier).unlock(_password.text);
      // The router moves on once the session is unlocked.
    } on WrongPassword {
      _failures++;
      _password.clear();
      _startWait(UnlockScreen.backoff(_failures));
      setState(() => _error = "That password didn't open this vault");
    } on VaultKeyMismatch {
      setState(
        () => _error =
            "vault.json was changed outside DevVault, so it isn't safe to "
            'open. Restore it from a backup or another device.',
      );
    } on Object {
      setState(() => _error = "Couldn't read the vault on this device");
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Cancelled or turned off: the password is next.
        _focus.requestFocus();
      }
    }
  }

  void _startWait(Duration wait) {
    _waitTimer?.cancel();
    if (wait == Duration.zero) return;
    setState(() => _wait = wait);
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _wait -= const Duration(seconds: 1));
      if (_wait <= Duration.zero) {
        timer.cancel();
        setState(() => _wait = Duration.zero);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final session = ref.watch(vaultSessionProvider);
    final header = session is Locked ? session.header : null;
    final waiting = _wait > Duration.zero;
    final biometric = ref.watch(biometricUnlockProvider).value;
    final biometry = biometric != null && biometric.enabled
        ? biometric.biometry
        : null;

    if (DesktopTheme.maybeOf(context) != null) {
      return DesktopUnlockView(
        header: header,
        password: _password,
        focusNode: _focus,
        notice: _notice,
        error: _error,
        busy: _busy,
        wait: _wait,
        biometry: biometry,
        onChanged: () => setState(() {}),
        onUnlock: _unlock,
        onBiometrics: _unlockWithBiometrics,
        onRecover: () => context.go(Routes.recover),
      );
    }

    return Scaffold(
      backgroundColor: bc.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BCSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: bc.surface,
                      shape: BCShapes.continuous(BCRadius.xxxl),
                    ),
                    child: SizedBox.square(
                      dimension: 80,
                      child: Icon(
                        LucideIcons.vault,
                        size: 36,
                        color: bc.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: BCSpacing.md),
                  const BCText(
                    'Unlock your vault',
                    type: BCTextType.h2,
                    align: TextAlign.center,
                  ),
                  const SizedBox(height: BCSpacing.sm),
                  if (header != null)
                    MonoText(
                      'vault ${header.vaultId}',
                      middleEllipsis: true,
                      style: TextStyle(
                        fontSize: BCTypography.sizeXs,
                        color: bc.muted,
                      ),
                    ),
                  const SizedBox(height: BCSpacing.xl),
                  if (_notice case final notice?) ...[
                    BCText(
                      notice,
                      type: BCTextType.bodySm,
                      color: BCTextColor.muted,
                      align: TextAlign.center,
                    ),
                    const SizedBox(height: BCSpacing.md),
                  ],
                  PasswordField(
                    label: 'Master password',
                    controller: _password,
                    // Focused once it's known whether a biometric prompt
                    // comes first: the keyboard would cover it.
                    focusNode: _focus,
                    isDisabled: _busy || waiting,
                    error: _error,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _unlock(),
                  ),
                  const SizedBox(height: BCSpacing.md),
                  BCButton(
                    fullWidth: true,
                    isDisabled: _busy || waiting || _password.text.isEmpty,
                    onPressed: _unlock,
                    startContent: _busy
                        ? const BCSpinner(size: BCSpinnerSize.sm)
                        : null,
                    endContent: _busy || waiting
                        ? null
                        : const Icon(LucideIcons.cornerDownLeft, size: 16),
                    child: Text(
                      waiting
                          ? 'Try again in ${_wait.inSeconds} s'
                          : _busy
                          ? 'Unlocking…'
                          : 'Unlock',
                    ),
                  ),
                  if (biometry != null) ...[
                    const SizedBox(height: BCSpacing.sm),
                    BCButton(
                      fullWidth: true,
                      variant: BCButtonVariant.secondary,
                      isDisabled: _busy,
                      onPressed: () => _unlockWithBiometrics(biometry),
                      startContent: Icon(
                        biometry == Biometry.faceId
                            ? LucideIcons.scanFace
                            : LucideIcons.fingerprint,
                        size: 16,
                      ),
                      child: Text('Unlock with ${biometry.label}'),
                    ),
                  ],
                  const SizedBox(height: BCSpacing.lg),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: BCSpacing.xs,
                    children: [
                      const BCText(
                        'Forgot your password?',
                        type: BCTextType.bodySm,
                        color: BCTextColor.muted,
                      ),
                      BCLinkButton(
                        onPressed: () => context.go(Routes.recover),
                        child: const Text('Use your recovery key'),
                      ),
                    ],
                  ),
                  if (header != null) ...[
                    const SizedBox(height: BCSpacing.xl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: BCSpacing.xs,
                      children: [
                        Icon(LucideIcons.shield, size: 13, color: bc.muted),
                        BCText(
                          'Argon2id · '
                          '${header.kdf.memLimit ~/ (1024 * 1024)} MiB · '
                          '${header.kdf.opsLimit} '
                          '${header.kdf.opsLimit == 1 ? 'pass' : 'passes'}',
                          type: BCTextType.bodyXs,
                          color: BCTextColor.muted,
                        ),
                      ],
                    ),
                    const SizedBox(height: BCSpacing.xs),
                    const BCText(
                      'Your password never leaves this device',
                      type: BCTextType.bodyXs,
                      color: BCTextColor.muted,
                      align: TextAlign.center,
                    ),
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
