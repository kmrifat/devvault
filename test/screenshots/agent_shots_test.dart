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

  Future<void> Function(WidgetTester) ask(Delivery delivery) => (tester) async {
    final c = appContainer(tester);
    final index = (c.read(vaultSessionProvider) as Unlocked).index;
    c
        .read(agentBridgeProvider.notifier)
        .debugAsk(sampleSecretPrompt(index, delivery: delivery));
  };

  for (final (name, delivery) in [
    ('N09-agent-reveal', const Delivery.reveal()),
    ('N09-agent-file', const Delivery.file('/Users/me/kitchenly/upload.jks')),
    (
      'N09-agent-command',
      const Delivery.command(
        r'./gradlew bundleRelease -Pstore.password="$STORE_PASSWORD"',
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
