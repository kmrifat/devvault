import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/providers.dart';
import '../../data/sync_controller.dart';
import '../../data/sync_setup.dart';
import '../../services/credential_store.dart';
import '../../shared/ui.dart';
import 'storage_form.dart';
import 'settings_layout.dart';

/// Design frame D07: where the vault syncs. Pick a provider (Cloudflare R2
/// first), enter the bucket and access keys, test the connection, then
/// save. Keys go to this device's keychain; the vault and the bucket only
/// ever hold ciphertext and `vault.json`.
class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  late final _form = StorageFormModel(ref.read(syncSetupProvider))
    ..addListener(_changed);
  bool _busy = false;

  /// The last test, valid only for the values it ran with.
  StorageCapabilities? _tested;
  String? _testedFor;
  String? _testError;

  @override
  void dispose() {
    _form
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  bool get _testPassed => _tested != null && _testedFor == _form.fingerprint;

  Future<void> _test() async {
    setState(() {
      _testError = null;
      _tested = null;
    });
    if (!_form.validate()) return;
    setState(() => _busy = true);
    final fingerprint = _form.fingerprint;
    try {
      final capabilities = await ref
          .read(syncSetupProvider.notifier)
          .test(_form.settings, _form.credentials);
      if (!mounted) return;
      setState(() {
        _tested = capabilities;
        _testedFor = fingerprint;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _testError = storageErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_testPassed || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(syncSetupProvider.notifier)
          .save(_form.settings, _form.credentials, _tested!);
      if (!mounted) return;
      BCToast.show(
        context,
        BCToastData(
          title: 'Sync is on',
          description: 'Syncing with ${_form.provider.label}.',
          variant: BCToastVariant.success,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Turn off sync on this device?',
      message:
          'This device stops syncing and forgets the access keys. The vault '
          'stays here, and what is already in the bucket stays there.',
      confirmLabel: 'Turn off',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await ref.read(syncSetupProvider.notifier).turnOff();
    if (!mounted) return;
    _form.secretKey.clear();
    setState(() => _tested = null);
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final setup = ref.watch(syncSetupProvider);

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
                  // Phones have no sidebar to go back with.
                  if (SettingsLayout.isNarrow(context) && context.canPop())
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BCButton(
                        variant: BCButtonVariant.ghost,
                        size: BCButtonSize.sm,
                        onPressed: () => context.pop(),
                        startContent: const Icon(
                          LucideIcons.chevronLeft,
                          size: 16,
                        ),
                        child: const Text('Settings'),
                      ),
                    ),
                  const BCText('Sync storage', type: BCTextType.h2),
                  const SizedBox(height: BCSpacing.sm),
                  const BCText(
                    'Sync through an S3-compatible bucket you own. Everything is '
                    'encrypted on this device first: the bucket only ever sees '
                    'ciphertext and vault.json.',
                    color: BCTextColor.muted,
                  ),
                  if (setup != null) ...[
                    const SizedBox(height: BCSpacing.lg),
                    _CurrentSetup(setup: setup, onTurnOff: _turnOff),
                  ],
                  StorageFormView(model: _form),
                  const SizedBox(height: BCSpacing.lg),
                  if (_testError case final error?)
                    StorageResult(
                      icon: LucideIcons.circleAlert,
                      tint: bc.danger,
                      title: 'Connection failed',
                      lines: [error],
                    )
                  else if (_testPassed)
                    StorageResult(
                      icon: _tested!.isRaceFree
                          ? LucideIcons.circleCheck
                          : LucideIcons.triangleAlert,
                      tint: _tested!.isRaceFree ? bc.success : bc.warning,
                      title: _tested!.isRaceFree
                          ? 'Connected · conditional writes enforced'
                          : 'Connected, with a limitation',
                      lines: _tested!.warnings,
                    ),
                  const SizedBox(height: BCSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    spacing: BCSpacing.sm,
                    children: [
                      BCButton(
                        variant: BCButtonVariant.secondary,
                        isDisabled: _busy,
                        onPressed: _test,
                        startContent: _busy
                            ? const BCSpinner(size: BCSpinnerSize.sm)
                            : const Icon(LucideIcons.plugZap, size: 16),
                        child: const Text('Test connection'),
                      ),
                      BCButton(
                        isDisabled: _busy || !_testPassed,
                        onPressed: _save,
                        child: Text(
                          setup == null ? 'Turn on sync' : 'Save changes',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentSetup extends ConsumerWidget {
  const _CurrentSetup({required this.setup, required this.onTurnOff});

  final SyncSetup setup;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bc = context.bcTheme;
    final s = setup.settings;
    final warnings = setup.capabilities?.warnings ?? const <String>[];
    return BCCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: BCSpacing.sm,
        children: [
          Row(
            spacing: BCSpacing.sm,
            children: [
              Icon(LucideIcons.cloudCheck, color: bc.success, size: 20),
              Expanded(
                child: BCText(
                  'Syncing with ${s.provider.label} · ${s.bucket}'
                  '${s.rootPrefix.isEmpty ? '' : '/${s.rootPrefix}'}',
                  weight: BCTextWeight.semibold,
                ),
              ),
              BCButton(
                size: BCButtonSize.sm,
                variant: BCButtonVariant.secondary,
                onPressed: () =>
                    ref.read(syncControllerProvider.notifier).syncNow(),
                child: const Text('Sync now'),
              ),
              BCButton(
                size: BCButtonSize.sm,
                variant: BCButtonVariant.dangerSoft,
                onPressed: onTurnOff,
                child: const Text('Turn off'),
              ),
            ],
          ),
          for (final w in warnings)
            BCText(w, type: BCTextType.bodySm, color: BCTextColor.muted),
          if (ref.watch(credentialStoreProvider) case FallbackCredentialStore(
            isDegraded: true,
          ))
            const BCText(
              'This device has no keychain (on Linux: no Secret Service such '
              'as GNOME Keyring or KWallet), so the access keys are kept only '
              'until DevVault quits. Enter them here again after a restart.',
              type: BCTextType.bodySm,
              color: BCTextColor.muted,
            ),
        ],
      ),
    );
  }
}
