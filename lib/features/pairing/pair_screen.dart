import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/routes.dart';
import '../../core/pairing.dart';
import '../../data/providers.dart';
import '../../data/sync_setup.dart';
import '../../data/vault_session.dart';
import '../../shared/desktop_ui.dart';
import '../../shared/ui.dart';

/// Opens Pair a device: a sheet on desktop (frame N08), the full-screen
/// [Routes.pair] on phones.
Future<void> showPairDevice(BuildContext context) {
  if (DesktopTheme.maybeOf(context) != null) {
    return showDesktopSheet<void>(
      context,
      builder: (_) => const PairScreen(inSheet: true),
    );
  }
  return context.push<void>(Routes.pair);
}

/// Pair a device (P4-06): a QR code holding this vault's sync storage
/// settings and keys, sealed under the 8-character code shown beside it.
/// It lasts ten minutes. The other device scans it (or pastes the text),
/// types the code, then joins with the master password: the vault key is
/// never in the QR.
///
/// Nothing is stored: the code and the payload live in this screen only.
///
/// On desktop it is drawn as a sheet: inside a real one when opened with
/// [showPairDevice], or over an empty window when [Routes.pair] is opened
/// directly.
class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key, this.inSheet = false});

  /// Shown by [showPairDevice] in a desktop sheet, rather than as a route.
  final bool inSheet;

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
    final guard = ref.read(clipboardGuardProvider);
    // The time this copy is cleared after: the setting, read by the guard.
    final after = guard.clearAfter;
    await guard.copySecret(payload);
    if (!mounted) return;
    showAppToast(
      context,
      BCToastData(
        title: 'Pairing text copied',
        description:
            'Paste it on the other device. It clears from the clipboard '
            'in ${after.inSeconds} seconds.',
        variant: BCToastVariant.success,
      ),
    );
  }

  void _close() {
    if (widget.inSheet) {
      Navigator.of(context).pop();
    } else {
      context.canPop() ? context.pop() : context.go(Routes.settings);
    }
  }

  /// Closes, then opens Settings › Sync to set up storage.
  void _setUpSync() {
    final router = GoRouter.of(context);
    if (widget.inSheet) Navigator.of(context).pop();
    router.go(Routes.settingsSync);
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(syncSetupProvider);
    final expiresAt = _expiresAt;
    final left = expiresAt?.difference(_now.toUtc());
    final expired = left != null && left <= Duration.zero;
    if (DesktopTheme.maybeOf(context) != null) {
      return _desktop(context, setup: setup, left: left, expired: expired);
    }
    final bc = context.bcTheme;

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

  /// Desktop (frame N08): the QR beside the instructions, the code and its
  /// countdown; New Code and Copy Pairing Text bottom left, Done bottom
  /// right.
  Widget _desktop(
    BuildContext context, {
    required SyncSetup? setup,
    required Duration? left,
    required bool expired,
  }) {
    final colors = context.desktopColors;
    final code = _code;
    final payload = _payload;
    final ready = setup != null && code != null && payload != null;

    final Widget content;
    if (setup == null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          const Text(
            'Set up sync first',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            "Pairing hands over where this vault syncs. It doesn't sync "
            'anywhere yet.',
            style: TextStyle(color: colors.secondaryText),
          ),
        ],
      );
    } else if (_error case final error?) {
      content = Text(error, style: TextStyle(color: colors.danger));
    } else if (!ready) {
      content = const SizedBox(
        height: _DesktopQr.extent,
        child: Center(
          child: DesktopProgress(
            size: 20,
            semanticLabel: 'Making a pairing code',
          ),
        ),
      );
    } else {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 20,
        children: [
          _DesktopQr(payload: payload, expired: expired),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Text(
                  'On the new device, choose “Join your vault”, then scan '
                  'this code (or paste the text) and type the code below. It '
                  'hands over where this vault syncs and the keys to that '
                  'storage, never the vault key: the new device still needs '
                  'your master password.',
                  style: TextStyle(
                    fontSize: DesktopMetrics.secondarySize + 1,
                    height: 1.45,
                    color: colors.text,
                  ),
                ),
                _DesktopCode(code: code, expired: expired),
                _Countdown(left: left!, expired: expired),
              ],
            ),
          ),
        ],
      );
    }

    final sheet = DesktopSheet(
      width: 640,
      title: 'Pair a device',
      leadingAction: setup == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                DesktopButton(
                  label: 'New Code',
                  onPressed: _making ? null : _make,
                ),
                if (ready && !expired)
                  DesktopButton(label: 'Copy Pairing Text', onPressed: _copy),
              ],
            ),
      actions: setup == null
          ? [
              DesktopButton(label: 'Cancel', onPressed: _close),
              DesktopButton(
                label: 'Set Up Sync…',
                kind: DesktopButtonKind.primary,
                onPressed: _setUpSync,
              ),
            ]
          : [
              DesktopButton(
                label: 'Done',
                kind: DesktopButtonKind.primary,
                onPressed: _close,
              ),
            ],
      child: content,
    );
    if (widget.inSheet) return sheet;
    // Opened as a route (a link, or Settings today): the same sheet, over
    // an empty window.
    return ColoredBox(color: colors.sidebar, child: sheet);
  }
}

/// The QR on desktop: dark on white whatever the app's appearance, so any
/// camera reads it, in a white rounded box.
class _DesktopQr extends StatelessWidget {
  const _DesktopQr({required this.payload, required this.expired});

  final String payload;
  final bool expired;

  static const double _padding = 12;
  static const double _size = 232;

  /// The box's edge.
  static const double extent = _size + 2 * _padding;

  @override
  Widget build(BuildContext context) {
    // Always the light palette: a camera needs dark on light.
    const light = DesktopColors.light;
    return Semantics(
      label: expired ? 'Expired pairing QR code' : 'Pairing QR code',
      image: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: light.groupBoxInner,
          border: Border.all(color: light.groupBoxStroke, width: 0.5),
          borderRadius: const BorderRadius.all(
            Radius.circular(DesktopMetrics.menuRadius + 2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_padding),
          child: Opacity(
            opacity: expired ? 0.08 : 1,
            child: QrImageView(
              data: payload,
              size: _size,
              padding: EdgeInsets.zero,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: light.text,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: light.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The code to type on the other device, large, in a field-like box.
class _DesktopCode extends StatelessWidget {
  const _DesktopCode({required this.code, required this.expired});

  final String code;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    return Semantics(
      label: 'Pairing code',
      value: Pairing.display(code),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.field,
          border: Border.all(color: colors.fieldStroke, width: 0.5),
          borderRadius: const BorderRadius.all(
            Radius.circular(DesktopMetrics.menuRadius + 2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            Pairing.display(code),
            textAlign: TextAlign.center,
            style: AppText.mono(context, fontSize: 20).copyWith(
              fontWeight: FontWeight.w500,
              letterSpacing: 2,
              color: expired ? colors.tertiaryText : colors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// How long the code still works, or that it has expired.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.left, required this.expired});

  final Duration left;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    final minutes = left.inMinutes;
    final seconds = (left.inSeconds % 60).toString().padLeft(2, '0');
    final color = expired ? colors.danger : colors.secondaryText;
    return Row(
      spacing: 5,
      children: [
        DesktopIcon(DesktopSymbol.timer, size: 12, color: color),
        Expanded(
          child: Text(
            expired
                ? 'Expired. Make a new code.'
                : 'Works for $minutes:$seconds, then the code expires',
            style: TextStyle(
              fontSize: DesktopMetrics.secondarySize,
              color: color,
            ),
          ),
        ),
      ],
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
