import 'package:vault_core/vault_core.dart';

/// Fills [vault] with the credentials shown in the design frames (D03, B2):
/// two apps across iOS, Android, Web and a server, items expiring soon and
/// expired, tags, and one item without an app. [now] is the test clock.
Future<void> seedSampleVault(Vault vault, DateTime now) async {
  final kitchenly = await vault.putApp(
    vault.newApp(
      name: 'Kitchenly',
      bundleIds: ['com.kitchenly.app'],
      packageNames: ['com.kitchenly.android'],
    ),
  );
  final ledgerly = await vault.putApp(vault.newApp(name: 'Ledgerly'));

  ItemField field(String value, {bool secret = false}) =>
      ItemField(value: value, source: FieldSource.file, secret: secret);

  Future<void> add(
    ItemType type,
    String title, {
    AppRecord? app,
    String? platform,
    String? environment,
    List<String> tags = const [],
    Map<String, ItemField> fields = const {},
    DateTime? expiresAt,
  }) async {
    final item = vault
        .newItem(type: type, title: title, fields: fields)
        .copyWith(
          appId: app?.id,
          platform: platform,
          environment: environment,
          tags: tags,
          expiresAt: expiresAt,
          expiresSource: expiresAt == null ? null : ExpirySource.file,
        );
    await vault.putItem(item);
  }

  // Kitchenly · Android
  await add(
    ItemType.androidKeystore,
    'Upload keystore',
    app: kitchenly,
    platform: 'android',
    environment: 'production',
    tags: ['release', 'signing'],
    fields: {
      'alias': field('upload'),
      'store_password': field('kitchenly-store-pass', secret: true),
    },
    expiresAt: DateTime.utc(2051, 1, 14),
  );
  await add(
    ItemType.gcpServiceAccount,
    'Play publisher',
    app: kitchenly,
    platform: 'android',
    environment: 'production',
    tags: ['ci', 'release'],
    fields: {'client_email': field('play@kitchenly.iam.gserviceaccount.com')},
    expiresAt: now.add(const Duration(days: 12)),
  );
  await add(
    ItemType.firebaseConfig,
    'Firebase config',
    app: kitchenly,
    platform: 'android',
    environment: 'production',
    fields: {'project_id': field('kitchenly-prod')},
  );
  await add(
    ItemType.oauthClient,
    'Google Sign-In client',
    app: kitchenly,
    platform: 'android',
    environment: 'production',
  );
  await add(
    ItemType.genericSecret,
    'Maps API key',
    app: kitchenly,
    platform: 'android',
    environment: 'production',
    fields: {'value': field('AIzaSyD-sample-maps-key', secret: true)},
  );
  await add(
    ItemType.firebaseConfig,
    'Firebase config',
    app: kitchenly,
    platform: 'android',
    environment: 'staging',
    fields: {'project_id': field('kitchenly-staging')},
  );

  // Kitchenly · iOS
  await add(
    ItemType.appleAuthKey,
    'APNs auth key',
    app: kitchenly,
    platform: 'ios',
    environment: 'production',
    tags: ['push'],
    fields: {'key_id': field('7KQ2M9XH4D'), 'team_id': field('9TW3C2P4LQ')},
  );
  await add(
    ItemType.appleCertificate,
    'Distribution certificate',
    app: kitchenly,
    platform: 'ios',
    environment: 'production',
    tags: ['signing'],
    expiresAt: now.subtract(const Duration(days: 3)),
  );
  await add(
    ItemType.provisioningProfile,
    'App Store profile',
    app: kitchenly,
    platform: 'ios',
    environment: 'production',
    tags: ['release'],
    expiresAt: now.add(const Duration(days: 20)),
  );

  // Kitchenly · Web
  await add(
    ItemType.oauthClient,
    'Web OAuth client',
    app: kitchenly,
    platform: 'web',
    environment: 'production',
  );

  // Ledgerly · Server
  await add(
    ItemType.genericSecret,
    'Stripe secret key',
    app: ledgerly,
    platform: 'server',
    environment: 'production',
    fields: {'value': field('sk_live_sample', secret: true)},
  );

  // No app
  await add(ItemType.genericFile, 'GitHub deploy key', tags: ['ci']);
}
