@Tags(['golden'])
library;

import 'package:agent_bridge/agent_bridge.dart' show Delivery;
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/agent_bridge.dart';
import 'package:devvault/data/app_settings.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

import '../agent_prompts.dart';
import '../agent_settings.dart';
import '../test_overrides.dart';
import 'harness.dart';

/// AI agents (P5): the approval sheet (N09) for each delivery, pairing
/// (N09b), the unlock screen while an agent waits, and Settings › AI
/// Agents (N07d).
void main() {
  setUpAll(loadAppFonts);

  /// [delivery] gets the upload keystore's id, for a command's variables.
  Future<void> Function(WidgetTester) ask(
    Delivery Function(String) delivery,
  ) => (tester) async {
    final c = appContainer(tester);
    final index = (c.read(vaultSessionProvider) as Unlocked).index;
    final keystore = index.all.firstWhere((i) => i.title == 'Upload keystore');
    c
        .read(agentBridgeProvider.notifier)
        .debugAsk(sampleSecretPrompt(index, delivery: delivery(keystore.id)));
  };

  for (final (name, delivery) in [
    ('N09-agent-reveal', (_) => const Delivery.reveal()),
    (
      'N09-agent-file',
      (_) => const Delivery.file('/Users/me/kitchenly/upload.jks'),
    ),
    (
      'N09-agent-command',
      (String id) => Delivery.command(
        r'./gradlew bundleRelease -Pstore.password="$STORE_PASSWORD" '
        r'-Pkey.password="$KEY_PASSWORD"',
        cwd: '/Users/me/kitchenly/android',
        env: {
          'STORE_PASSWORD': '$id#store_password',
          'KEY_PASSWORD': '$id#key_password',
        },
      ),
    ),
  ]) {
    shot(name, Routes.vault(), sample: true, interact: ask(delivery));
    shot(
      '$name-light',
      Routes.vault(),
      sample: true,
      interact: ask(delivery),
      brightness: Brightness.light,
    );
  }

  for (final kit in otherKits) {
    shot(
      'N09-agent-reveal-${kit.name}-light',
      Routes.vault(),
      sample: true,
      interact: ask((_) => const Delivery.reveal()),
      brightness: Brightness.light,
      kit: kit,
    );
  }

  shot(
    'N09b-agent-pair-light',
    Routes.vault(),
    sample: true,
    brightness: Brightness.light,
    interact: (tester) async {
      // Not awaited: it resolves when someone answers.
      appContainer(tester)
          .read(agentBridgeProvider.notifier)
          .debugAsk(samplePairPrompt());
    },
  );

  shot(
    'N00-unlock-agent-waiting-light',
    Routes.unlock,
    vault: TestVault.locked,
    brightness: Brightness.light,
    interact: (tester) async => appContainer(tester)
        .read(agentBridgeProvider.notifier)
        .debugWait(
          const AgentWait(client: 'claude-code', what: 'for a secret'),
        ),
  );

  // Settings › AI Agents: on, two clients, a few things they did.
  Future<void> activity(WidgetTester tester) async {
    final bridge = appContainer(tester).read(agentBridgeProvider.notifier);
    for (final entry in sampleActivity.reversed) {
      bridge.debugLog(entry);
    }
  }

  final agentsOn = [
    ...agentSettingsOverrides(),
    initialSettingsProvider.overrideWithValue(
      const AppSettings(agentsEnabled: true),
    ),
  ];
  shot(
    'N07d-settings-agents',
    Routes.settingsAgents,
    sample: true,
    overrides: agentsOn,
    interact: activity,
  );
  shot(
    'N07d-settings-agents-light',
    Routes.settingsAgents,
    sample: true,
    overrides: agentsOn,
    interact: activity,
    brightness: Brightness.light,
  );
}
