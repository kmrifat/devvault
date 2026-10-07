import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/routes.dart';
import '../../core/pairing.dart';
import '../../data/providers.dart';
import '../../data/sync_setup.dart';
import '../../data/vault_session.dart';
import '../../shared/ui.dart';

/// Pair a device (P4-06): a QR code holding this vault's sync storage
/// settings and keys, sealed under the 8-character code shown beside it.
/// It lasts ten minutes. The other device scans it (or pastes the text),
/// types the code, then joins with the master password: the vault key is
/// never in the QR.
///
/// Nothing is stored: the code and the payload live in this screen only.
class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key});

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> {
  String? _code;
  String? _payload;
  DateTime? _expiresAt;
  bool _making = false;
  String? _error;
  Timer? _tick;

  DateTime get _now => ref.read(clockProvider)();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _payload != null) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _make());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _make() async {
    final setup = ref.read(syncSetupProvider);
    final session = ref.read(vaultSessionProvider);
    if (setup == null || session is! Unlocked || _making) return;
    final crypto = ref.read(cryptoProvider);
    final code = Pairing.newCode(crypto);
    final now = _now;
    setState(() {
      _making = true;
      _error = null;
      _payload = null;
    });
    try {
      final payload = await Pairing.seal(
        crypto: crypto,
        vaultId: session.vault.vaultId,
        settings: setup.settings,
        credentials: setup.credentials,
        code: code,
        now: now,
        ops: ref.read(pairingOpsLimitProvider),
        mem: ref.read(pairingMemLimitProvider),
      );
      if (!mounted) return;
      setState(() {
        _code = code;
        _payload = payload;
        _expiresAt = now.toUtc().add(Pairing.lifetime);
      });
    } on Object {
      if (mounted) setState(() => _error = "Couldn't make a pairing code.");
    } finally {
      if (mounted) setState(() => _making = false);
    }
  }

  Future<void> _copy() async {
    final payload = _payload;
    if (payload == null) return;
    await ref.read(clipboardGuardProvider).copySecret(payload);
    if (!mounted) return;
    BCToast.show(
      context,
      const BCToastData(
        title: 'Pairing text copied',
        description:
            'Paste it on the other device. It clears from the clipboard '
            'in 30 seconds.',
        variant: BCToastVariant.success,
      ),
    );
  }

  void _close() =>
      context.canPop() ? context.pop() : context.go(Routes.settings);

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final setup = ref.watch(syncSetupProvider);
    final expiresAt = _expiresAt;
    final left = expiresAt?.difference(_now.toUtc());
    final expired = left != null && left <= Duration.zero;

    return Scaffold(
      backgroundColor: bc.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BCCloseButton(onPressed: _close),
                  ),
                  const SizedBox(height: BCSpacing.md),
                  const BCText('Pair a device', type: BCTextType.h2),
                  const SizedBox(height: BCSpacing.sm),
                  const BCText(
                    'On the new device, choose “Join your vault”, then scan '
                    'this code (or paste the text) and type the code below. '
                    'It still needs your master password: the vault key is '
                    'never in the QR.',
                    color: BCTextColor.muted,
                  ),
                  const SizedBox(height: BCSpacing.xl),
                  if (setup == null)
                    BCEmptyState(
                      icon: const Icon(LucideIcons.cloudOff),
                      title: 'Set up sync first',
                      description:
                          'Pairing hands over where this vault syncs. It '
                          "doesn't sync anywhere yet.",
                      actions: [
                        BCButton(
                          onPressed: () => context.go(Routes.settingsSync),
                          child: const Text('Sync storage'),
                        ),
                      ],
                    )
                  else if (_error case final error?)
                    BCText(error, style: TextStyle(color: bc.danger))
                  else if (_payload == null || _code == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 64),
                      child: Center(child: BCSpinner()),
                    )
                  else ...[
                    _QrCard(payload: _payload!, expired: expired),
                    const SizedBox(height: BCSpacing.lg),
                    _CodeLine(code: _code!, left: left!, expired: expired),
                    const SizedBox(height: BCSpacing.lg),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: BCSpacing.sm,
                      runSpacing: BCSpacing.sm,
                      children: [
                        BCButton(
                          variant: expired
                              ? BCButtonVariant.primary
                              : BCButtonVariant.secondary,
                          isDisabled: _making,
                          onPressed: _make,
                          startContent: const Icon(
                            LucideIcons.refreshCw,
                            size: 15,
                          ),
                          child: const Text('New code'),
                        ),
                        if (!expired)
                          BCButton(
                            variant: BCButtonVariant.secondary,
                            onPressed: _copy,
                            startContent: const Icon(
                              LucideIcons.copy,
                              size: 15,
                            ),
                            child: const Text('Copy pairing text'),
                          ),
                      ],
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

/// The QR, always dark on light (the light theme's colours) so any camera
/// reads it, in either app theme.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.payload, required this.expired});

  final String payload;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Theme(
        data: AppTheme.light(),
        child: Builder(
          builder: (context) {
            final bc = context.bcTheme;
            return Semantics(
              label: expired ? 'Expired pairing QR code' : 'Pairing QR code',
              image: true,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: bc.background,
                  shape: BCShapes.continuous(BCRadius.xxl),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(BCSpacing.lg),
                  child: Opacity(
                    opacity: expired ? 0.08 : 1,
                    child: QrImageView(
                      data: payload,
                      size: 280,
                      padding: EdgeInsets.zero,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: bc.foreground,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: bc.foreground,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CodeLine extends StatelessWidget {
  const _CodeLine({
    required this.code,
    required this.left,
    required this.expired,
  });

  final String code;
  final Duration left;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final minutes = left.inMinutes;
    final seconds = (left.inSeconds % 60).toString().padLeft(2, '0');
    return Column(
      spacing: BCSpacing.xs,
      children: [
        const BCText('Code', type: BCTextType.bodySm, color: BCTextColor.muted),
        Semantics(
          label: 'Pairing code',
          value: Pairing.display(code),
          excludeSemantics: true,
          child: MonoText(
            Pairing.display(code),
            style: TextStyle(
              fontSize: 30,
              fontWeight: BCTypography.medium,
              letterSpacing: 2,
              color: expired ? bc.muted : bc.foreground,
            ),
          ),
        ),
        BCText(
          expired ? 'Expired. Make a new code.' : 'Works for $minutes:$seconds',
          type: BCTextType.bodySm,
          style: TextStyle(color: expired ? bc.danger : bc.muted),
        ),
      ],
    );
  }
}
