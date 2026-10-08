import 'package:agent_bridge/agent_bridge.dart' show Delivery;
import 'package:devvault/core/agent_item_meta.dart';
import 'package:devvault/data/agent_bridge.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

/// Agent prompts over the sample vault, for widget tests and screenshots.

PairPrompt samplePairPrompt({String client = 'claude-code'}) =>
    PairPrompt(id: 1, client: client, at: testNow);

/// claude-code asking for the upload keystore's passwords and file.
SecretPrompt sampleSecretPrompt(
  VaultIndex index, {
  required Delivery delivery,
}) {
  final keystore = index.all.firstWhere((i) => i.title == 'Upload keystore');
  return SecretPrompt(
    id: 2,
    client: 'claude-code',
    at: testNow,
    reason: 'Sign the Android release build',
    delivery: delivery,
    items: [
      SecretPromptItem(
        item: keystore,
        path: agentItemPath(keystore, index.apps[keystore.appId]),
        names: [
          'store_password',
          'key_password',
          keystore.attachments.single.filename,
        ],
      ),
    ],
  );
}
