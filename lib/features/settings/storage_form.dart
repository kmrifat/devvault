import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

import '../../data/sync_setup.dart';
import '../../shared/ui.dart';

/// What the storage form holds: the provider, bucket and keys being typed.
/// Shared by Settings → Sync storage (D07) and joining a vault (P2-10).
class StorageFormModel extends ChangeNotifier {
  StorageFormModel([SyncSetup? setup]) {
    final s = setup?.settings ?? const SyncSettings();
    provider = s.provider;
    pathStyle = s.pathStyle;
    accountId.text = s.accountId;
    endpoint.text = s.endpoint;
    region.text = s.region;
    bucket.text = s.bucket;
    prefix.text = s.prefix;
    accessKey.text = setup?.credentials.accessKeyId ?? '';
    secretKey.text = setup?.credentials.secretAccessKey ?? '';
    for (final c in _all) {
      c.addListener(notifyListeners);
    }
  }

  late StorageProvider provider;
  late bool pathStyle;
  final accountId = TextEditingController();
  final endpoint = TextEditingController();
  final region = TextEditingController();
  final bucket = TextEditingController();
  final prefix = TextEditingController();
  final accessKey = TextEditingController();
  final secretKey = TextEditingController();

  Map<String, String> errors = const {};

  List<TextEditingController> get _all => [
    accountId,
    endpoint,
    region,
    bucket,
    prefix,
    accessKey,
    secretKey,
  ];

  /// Fills every field from [settings] and [credentials], e.g. from a
  /// pairing code (P4-06).
  void fill(SyncSettings settings, AwsCredentials credentials) {
    provider = settings.provider;
    pathStyle = settings.pathStyle;
    accountId.text = settings.accountId;
    endpoint.text = settings.endpoint;
    region.text = settings.region;
    bucket.text = settings.bucket;
    prefix.text = settings.prefix;
    accessKey.text = credentials.accessKeyId;
    secretKey.text = credentials.secretAccessKey;
    notifyListeners();
  }

  void setProvider(StorageProvider value) {
    provider = value;
    notifyListeners();
  }

  void setPathStyle(bool value) {
    pathStyle = value;
    notifyListeners();
  }

  SyncSettings get settings => SyncSettings(
    provider: provider,
    accountId: accountId.text,
    endpoint: endpoint.text,
    region: region.text,
    bucket: bucket.text,
    prefix: prefix.text,
    pathStyle: provider == StorageProvider.r2 ? true : pathStyle,
  );

  AwsCredentials get credentials => AwsCredentials(
    accessKeyId: accessKey.text.trim(),
    secretAccessKey: secretKey.text.trim(),
  );

  /// Changes whenever any value does; a test result is valid only for the
  /// fingerprint it ran with. Holds a hash of the secret, not the secret.
  String get fingerprint =>
      '${settings.toJson()}|${accessKey.text}|${secretKey.text.hashCode}';

  /// Checks every field and shows the problems; true when there are none.
  bool validate() {
    errors = {
      ...settings.validate(),
      if (accessKey.text.trim().isEmpty) 'accessKey': 'Enter the access key ID',
      if (secretKey.text.trim().isEmpty)
        'secretKey': 'Enter the secret access key',
    };
    notifyListeners();
    return errors.isEmpty;
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.removeListener(notifyListeners);
    }
    secretKey.clear();
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }
}

/// The provider, bucket and access-key sections of the storage form.
class StorageFormView extends StatelessWidget {
  const StorageFormView({super.key, required this.model});

  final StorageFormModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final provider = model.provider;
        final errors = model.errors;
        final usesEndpoint =
            provider == StorageProvider.minio ||
            provider == StorageProvider.custom;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StorageSection('Provider'),
            BCCard(
              child: BCRadioGroup<StorageProvider>(
                value: provider,
                onValueChange: model.setProvider,
                children: [
                  for (final p in StorageProvider.values)
                    BCRadio(
                      value: p,
                      label: p.label,
                      description: switch (p) {
                        StorageProvider.r2 =>
                          'Recommended: no egress fees, generous free tier',
                        StorageProvider.aws => null,
                        StorageProvider.b2 => 'Through its S3-compatible API',
                        StorageProvider.minio => 'Self-hosted',
                        StorageProvider.custom =>
                          'Any store with conditional writes',
                      },
                    ),
                ],
              ),
            ),
            const StorageSection('Bucket'),
            BCCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: BCSpacing.md,
                children: [
                  if (provider == StorageProvider.r2)
                    StorageField(
                      label: 'Account ID',
                      controller: model.accountId,
                      hint: '32 hex characters',
                      error: errors['accountId'],
                    ),
                  if (usesEndpoint)
                    StorageField(
                      label: 'Endpoint',
                      controller: model.endpoint,
                      hint: 'https://s3.example.com',
                      error: errors['endpoint'],
                    ),
                  if (provider != StorageProvider.r2)
                    StorageField(
                      label: usesEndpoint ? 'Region (optional)' : 'Region',
                      controller: model.region,
                      hint: switch (provider) {
                        StorageProvider.aws => 'eu-west-1',
                        StorageProvider.b2 => 'us-west-004',
                        _ => 'us-east-1',
                      },
                      error: errors['region'],
                    ),
                  StorageField(
                    label: 'Bucket',
                    controller: model.bucket,
                    hint: 'my-devvault',
                    error: errors['bucket'],
                  ),
                  StorageField(
                    label: 'Folder (optional)',
                    controller: model.prefix,
                    hint: 'devvault',
                    error: errors['prefix'],
                  ),
                  if (provider != StorageProvider.r2)
                    Row(
                      children: [
                        const Expanded(
                          child: BCText(
                            'Path-style addressing',
                            type: BCTextType.bodySm,
                          ),
                        ),
                        BCSwitch(
                          isSelected: model.pathStyle,
                          onSelectedChange: model.setPathStyle,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const StorageSection('Access keys'),
            BCCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: BCSpacing.md,
                children: [
                  StorageField(
                    label: 'Access key ID',
                    controller: model.accessKey,
                    error: errors['accessKey'],
                  ),
                  PasswordField(
                    label: 'Secret access key',
                    controller: model.secretKey,
                    error: errors['secretKey'],
                    description:
                        'Kept in this device’s keychain, never in the vault '
                        'or the bucket.',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class StorageSection extends StatelessWidget {
  const StorageSection(this.title, {super.key});

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

class StorageField extends StatelessWidget {
  const StorageField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.error,
  });

  final String label;
  final TextEditingController controller;
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
        ),
        if (error case final e?) BCTextFieldError(e),
      ],
    );
  }
}

/// A result card: an icon, a title and explanatory lines.
class StorageResult extends StatelessWidget {
  const StorageResult({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    this.lines = const [],
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

/// Plain words for a storage error, for "Test connection" and joining.
String storageErrorMessage(Object error) => switch (error) {
  StorageAccessDenied() =>
    'The storage refused these keys. Check the key ID, the secret and that '
        'the key may read and write this bucket.',
  StorageNotFound() =>
    'No bucket with that name here. Check the bucket and the account or '
        'region.',
  StorageUnavailable() =>
    "Couldn't reach the storage. Check the endpoint and your connection.",
  StorageException(:final message) =>
    'The storage answered unexpectedly: $message',
  _ => "Couldn't reach the storage. Check the endpoint.",
};
