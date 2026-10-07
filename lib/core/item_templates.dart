import 'package:vault_core/vault_core.dart';

/// A field a new item of some type usually has.
typedef FieldTemplate = ({String key, bool secret});

/// The fields the item form offers for each type, so a typed-in credential
/// gets the same names an imported one would. They start empty; the user
/// fills in what they have and removes the rest.
abstract final class ItemTemplates {
  static List<FieldTemplate> fieldsFor(ItemType type) => switch (type) {
    ItemType.appleAuthKey => [
      (key: 'key_id', secret: false),
      (key: 'team_id', secret: false),
    ],
    ItemType.appleCertificate => [
      (key: 'team_id', secret: false),
      (key: 'sha1', secret: false),
    ],
    ItemType.provisioningProfile => [
      (key: 'team_id', secret: false),
      (key: 'bundle_id', secret: false),
      (key: 'uuid', secret: false),
    ],
    ItemType.androidKeystore => [
      (key: 'alias', secret: false),
      (key: 'store_password', secret: true),
      (key: 'key_password', secret: true),
    ],
    ItemType.firebaseConfig => [
      (key: 'project_id', secret: false),
      (key: 'app_id', secret: false),
    ],
    ItemType.gcpServiceAccount => [
      (key: 'client_email', secret: false),
      (key: 'project_id', secret: false),
    ],
    ItemType.oauthClient => [
      (key: 'client_id', secret: false),
      (key: 'client_secret', secret: true),
    ],
    ItemType.sshKey => [
      (key: 'fingerprint', secret: false),
      (key: 'passphrase', secret: true),
    ],
    ItemType.genericSecret => [(key: 'value', secret: true)],
    ItemType.genericFile => [],
  };

  /// Platforms and environments the form suggests (SPEC §5); any other
  /// string an item already has is kept and offered too.
  static const platforms = [
    'ios',
    'android',
    'macos',
    'web',
    'server',
    'windows',
    'linux',
  ];
  static const environments = ['production', 'staging', 'development'];
}
