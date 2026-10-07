import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

import '../../data/sync_controller.dart';
import '../../data/sync_setup.dart';
import '../../shared/ui.dart';

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
  late StorageProvider _provider;
  late bool _pathStyle;
  final _accountId = TextEditingController();
  final _endpoint = TextEditingController();
  final _region = TextEditingController();
  final _bucket = TextEditingController();
  final _prefix = TextEditingController();
  final _accessKey = TextEditingController();
  final _secretKey = TextEditingController();

  Map<String, String> _errors = const {};
  bool _busy = false;

  /// The last test, valid only for the values it ran with.
  StorageCapabilities? _tested;
  String? _testedFor;
  String? _testError;

  @override
  void initState() {
    super.initState();
    final setup = ref.read(syncSetupProvider);
    final s = setup?.settings ?? const SyncSettings();
    _provider = s.provider;
    _pathStyle = s.pathStyle;
    _accountId.text = s.accountId;
    _endpoint.text = s.endpoint;
    _region.text = s.region;
    _bucket.text = s.bucket;
    _prefix.text = s.prefix;
    _accessKey.text = setup?.credentials.accessKeyId ?? '';
    _secretKey.text = setup?.credentials.secretAccessKey ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _accountId,
      _endpoint,
      _region,
      _bucket,
      _prefix,
      _accessKey,
    ]) {
      c.dispose();
    }
    _secretKey
      ..clear()
      ..dispose();
    super.dispose();
  }

  SyncSettings get _settings => SyncSettings(
    provider: _provider,
    accountId: _accountId.text,
    endpoint: _endpoint.text,
    region: _region.text,
    bucket: _bucket.text,
    prefix: _prefix.text,
    pathStyle: _provider == StorageProvider.r2 ? true : _pathStyle,
  );

  AwsCredentials get _credentials => AwsCredentials(
    accessKeyId: _accessKey.text.trim(),
    secretAccessKey: _secretKey.text.trim(),
  );

  /// What the test result is valid for (never includes the secret itself,
  /// only whether it changed).
  String get _fingerprint =>
      '${_settings.toJson()}|${_accessKey.text}|${_secretKey.text.hashCode}';

  bool get _testPassed => _tested != null && _testedFor == _fingerprint;

  Map<String, String> _validate() => {
    ..._settings.validate(),
    if (_accessKey.text.trim().isEmpty) 'accessKey': 'Enter the access key ID',
    if (_secretKey.text.trim().isEmpty)
      'secretKey': 'Enter the secret access key',
  };

  Future<void> _test() async {
    final errors = _validate();
    setState(() {
      _errors = errors;
      _testError = null;
      _tested = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final fingerprint = _fingerprint;
    try {
      final capabilities = await ref
          .read(syncSetupProvider.notifier)
          .test(_settings, _credentials);
      if (!mounted) return;
      setState(() {
        _tested = capabilities;
        _testedFor = fingerprint;
      });
    } on StorageAccessDenied {
      _fail(
        'The storage refused these keys. Check the key ID, the secret '
        'and that the key may read and write this bucket.',
      );
    } on StorageNotFound {
      _fail(
        'No bucket with that name here. Check the bucket and the '
        'account or region.',
      );
    } on StorageUnavailable {
      _fail(
        "Couldn't reach the storage. Check the endpoint and your "
        'connection.',
      );
    } on StorageException catch (e) {
      _fail('The storage answered unexpectedly: ${e.message}');
    } on Object {
      _fail("Couldn't reach the storage. Check the endpoint.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _testError = message);
  }

  Future<void> _save() async {
    if (!_testPassed || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(syncSetupProvider.notifier)
          .save(_settings, _credentials, _tested!);
      if (!mounted) return;
      BCToast.show(
        context,
        BCToastData(
          title: 'Sync is on',
          description: 'Syncing with ${_provider.label}.',
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
    _secretKey.clear();
    setState(() => _tested = null);
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final bc = context.bcTheme;
    final setup = ref.watch(syncSetupProvider);
    final usesEndpoint =
        _provider == StorageProvider.minio ||
        _provider == StorageProvider.custom;
    final usesRegion = _provider != StorageProvider.r2;

    return Scaffold(
      backgroundColor: bc.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                const _Section('Provider'),
                BCCard(
                  child: BCRadioGroup<StorageProvider>(
                    value: _provider,
                    onValueChange: (p) => setState(() => _provider = p),
                    children: [
                      for (final p in StorageProvider.values)
                        BCRadio(
                          value: p,
                          label: p.label,
                          description: switch (p) {
                            StorageProvider.r2 =>
                              'Recommended: no egress fees, generous free tier',
                            StorageProvider.aws => null,
                            StorageProvider.b2 =>
                              'Through its S3-compatible API',
                            StorageProvider.minio => 'Self-hosted',
                            StorageProvider.custom =>
                              'Any store with conditional writes',
                          },
                        ),
                    ],
                  ),
                ),
                const _Section('Bucket'),
                BCCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: BCSpacing.md,
                    children: [
                      if (_provider == StorageProvider.r2)
                        _Field(
                          label: 'Account ID',
                          controller: _accountId,
                          hint: '32 hex characters',
                          error: _errors['accountId'],
                          onChanged: _changed,
                        ),
                      if (usesEndpoint)
                        _Field(
                          label: 'Endpoint',
                          controller: _endpoint,
                          hint: 'https://s3.example.com',
                          error: _errors['endpoint'],
                          onChanged: _changed,
                        ),
                      if (usesRegion)
                        _Field(
                          label: usesEndpoint ? 'Region (optional)' : 'Region',
                          controller: _region,
                          hint: switch (_provider) {
                            StorageProvider.aws => 'eu-west-1',
                            StorageProvider.b2 => 'us-west-004',
                            _ => 'us-east-1',
                          },
                          error: _errors['region'],
                          onChanged: _changed,
                        ),
                      _Field(
                        label: 'Bucket',
                        controller: _bucket,
                        hint: 'my-devvault',
                        error: _errors['bucket'],
                        onChanged: _changed,
                      ),
                      _Field(
                        label: 'Folder (optional)',
                        controller: _prefix,
                        hint: 'devvault',
                        error: _errors['prefix'],
                        onChanged: _changed,
                      ),
                      if (_provider != StorageProvider.r2)
                        Row(
                          children: [
                            const Expanded(
                              child: BCText(
                                'Path-style addressing',
                                type: BCTextType.bodySm,
                              ),
                            ),
                            BCSwitch(
                              isSelected: _pathStyle,
                              onSelectedChange: (v) =>
                                  setState(() => _pathStyle = v),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const _Section('Access keys'),
                BCCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: BCSpacing.md,
                    children: [
                      _Field(
                        label: 'Access key ID',
                        controller: _accessKey,
                        error: _errors['accessKey'],
                        onChanged: _changed,
                      ),
                      PasswordField(
                        label: 'Secret access key',
                        controller: _secretKey,
                        error: _errors['secretKey'],
                        description:
                            'Kept in this device’s keychain, never in the '
                            'vault or the bucket.',
                        onChanged: (_) => _changed(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BCSpacing.lg),
                if (_testError case final error?)
                  _Result(
                    icon: LucideIcons.circleAlert,
                    tint: bc.danger,
                    title: 'Connection failed',
                    lines: [error],
                  )
                else if (_testPassed)
                  _Result(
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
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 24, 6, 8),
      child: BCText(
        title,
        type: BCTextType.bodySm,
        weight: BCTextWeight.medium,
        color: BCTextColor.muted,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.error,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? hint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return BCTextField(
      isInvalid: error != null,
      children: [
        BCTextFieldLabel(label),
        BCTextFieldInput(
          controller: controller,
          hintText: hint,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => onChanged(),
        ),
        if (error case final e?) BCTextFieldError(e),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.icon,
    required this.tint,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return BCCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: BCSpacing.sm,
        children: [
          Icon(icon, color: tint, size: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                BCText(title, weight: BCTextWeight.semibold),
                for (final line in lines)
                  BCText(
                    line,
                    type: BCTextType.bodySm,
                    color: BCTextColor.muted,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
