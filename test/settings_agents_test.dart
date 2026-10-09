import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/agent_bridge.dart';
import 'package:devvault/data/agent_clients.dart';
import 'package:devvault/data/providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_settings.dart';
import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> open(WidgetTester tester, {bool supported = true}) =>
      pumpUnlockedApp(
        tester,
        location: Routes.settingsAgents,
        layout: AppLayout.desktop,
        overrides: agentSettingsOverrides(supported: supported),
      );

  testWidgets('switches change the settings', (tester) async {
    await open(tester);
    final c = appContainer(tester);
    expect(c.read(settingsProvider).agentsEnabled, isFalse);
    expect(c.read(settingsProvider).agentMetadataWithoutAsking, isTrue);
    await tester.tap(find.text('Read metadata without asking'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).agentMetadataWithoutAsking, isFalse);
    expect(
      find.textContaining("claude mcp add --scope user devvault"),
      findsOneWidget,
    );
  });

  testWidgets('setup for each kind of agent', (tester) async {
    await open(tester);
    expect(find.text('Set up an agent'), findsOneWidget);
    expect(find.text('Run this once in a terminal:'), findsOneWidget);
    await tester.tap(find.text('Claude Code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex CLI').last);
    await tester.pumpAndSettle();
    expect(find.text('Add this to ~/.codex/config.toml:'), findsOneWidget);
    expect(find.textContaining('tool_timeout_sec = 150'), findsOneWidget);
  });

  testWidgets('keep running needs agents on', (tester) async {
    await open(tester);
    final c = appContainer(tester);
    await tester.tap(find.text('Keep running when the window is closed'));
    await tester.pumpAndSettle();
    // Agents are off: nothing to keep running for.
    expect(c.read(settingsProvider).keepRunningWhenClosed, isTrue);
    c.read(settingsProvider.notifier).setAgentsEnabled(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep running when the window is closed'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).keepRunningWhenClosed, isFalse);
  });

  testWidgets('macOS only for now', (tester) async {
    await open(tester, supported: false);
    expect(find.text('Available on macOS for now.'), findsOneWidget);
    await tester.tap(find.text('Allow AI agents'));
    await tester.pumpAndSettle();
    expect(appContainer(tester).read(settingsProvider).agentsEnabled, isFalse);
  });

  testWidgets('lists clients; Disconnect forgets one', (tester) async {
    await open(tester);
    expect(find.text('claude-code'), findsOneWidget);
    expect(find.text('cursor'), findsOneWidget);
    await tester.tap(find.text('Disconnect').first);
    await tester.pumpAndSettle();
    final clients = appContainer(tester).read(agentBridgeProvider).clients;
    expect(clients.map((c) => c.name), ['cursor']);
    expect(find.text('claude-code'), findsNothing);
  });

  testWidgets('shows recent activity, never values', (tester) async {
    await open(tester);
    appContainer(tester)
        .read(agentBridgeProvider.notifier)
        .debugLog(sampleActivity.first);
    await tester.pumpAndSettle();
    expect(find.text('Wrote file · Upload keystore'), findsOneWidget);
    expect(find.textContaining('Allowed once'), findsOneWidget);
  });

  test('PairedClient round-trips and drops bad entries', () {
    final client = sampleClients.first;
    expect(PairedClient.fromJson(client.toJson())!.name, client.name);
    expect(PairedClient.fromJson({'name': 'x'}), isNull);
    expect(
      PairedClient.fromJson({...client.toJson(), 'token_sha256': 'nothex'}),
      isNull,
    );
  });
}
