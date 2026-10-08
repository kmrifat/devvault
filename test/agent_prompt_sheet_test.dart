import 'package:agent_bridge/agent_bridge.dart' show Delivery;
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/agent_bridge.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_prompts.dart';
import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<AgentBridgeNotifier> open(WidgetTester tester) async {
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      vault: TestVault.sample,
      layout: AppLayout.desktop,
    );
    return appContainer(tester).read(agentBridgeProvider.notifier);
  }

  testWidgets('a secret prompt shows the reason, items and delivery', (
    tester,
  ) async {
    final bridge = await open(tester);
    final index =
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;
    final answer = bridge.debugAsk(
      sampleSecretPrompt(index, delivery: const Delivery.reveal()),
    );
    await tester.pumpAndSettle();

    expect(find.text('“claude-code” wants to see secrets'), findsOneWidget);
    expect(find.text('“Sign the Android release build”'), findsOneWidget);
    expect(
      find.text('Kitchenly › android › production › Upload keystore'),
      findsOneWidget,
    );
    expect(
      find.text('store_password · key_password · kitchenly-upload.jks'),
      findsOneWidget,
    );
    expect(find.textContaining('AI model'), findsOneWidget);
    // Never a value.
    expect(find.textContaining('kitchenly-store-pass'), findsNothing);

    await tester.tap(find.text('Allow Once'));
    await tester.pumpAndSettle();
    expect(await answer, AgentDecision.allowOnce);
    expect(find.text('Allow Once'), findsNothing);
  });

  testWidgets('a file delivery shows where it writes', (tester) async {
    final bridge = await open(tester);
    final index =
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;
    final answer = bridge.debugAsk(
      sampleSecretPrompt(
        index,
        delivery: const Delivery.file('/Users/me/kitchenly/upload.jks'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('“claude-code” wants to write secrets to a file'),
      findsOneWidget,
    );
    expect(find.text('/Users/me/kitchenly/upload.jks'), findsOneWidget);
    expect(find.textContaining('AI model'), findsNothing);
    await tester.tap(find.text('Allow for 15 Minutes'));
    await tester.pumpAndSettle();
    expect(await answer, AgentDecision.allowForAWhile);
  });

  testWidgets('pairing: Don’t Allow denies', (tester) async {
    final bridge = await open(tester);
    final answer = bridge.debugAsk(samplePairPrompt());
    await tester.pumpAndSettle();
    expect(
      find.text('“claude-code” wants to connect to DevVault'),
      findsOneWidget,
    );
    await tester.tap(find.text('Don’t Allow'));
    await tester.pumpAndSettle();
    expect(await answer, AgentDecision.deny);
  });

  testWidgets('Escape denies', (tester) async {
    final bridge = await open(tester);
    final answer = bridge.debugAsk(samplePairPrompt());
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(await answer, AgentDecision.deny);
  });

  testWidgets('prompts queue: the next shows when one is answered', (
    tester,
  ) async {
    final bridge = await open(tester);
    final first = bridge.debugAsk(samplePairPrompt());
    final second = bridge.debugAsk(samplePairPrompt(client: 'cursor'));
    await tester.pumpAndSettle();
    expect(find.textContaining('claude-code'), findsOneWidget);
    expect(find.textContaining('cursor'), findsNothing);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(await first, AgentDecision.allowOnce);
    expect(find.textContaining('cursor'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(await second, AgentDecision.allowOnce);
  });

  testWidgets('a prompt that closes elsewhere takes its sheet away', (
    tester,
  ) async {
    final bridge = await open(tester);
    final prompt = samplePairPrompt();
    final answer = bridge.debugAsk(prompt);
    await tester.pumpAndSettle();
    expect(find.text('Allow'), findsOneWidget);
    // As when the agent hangs up: answered elsewhere, the sheet goes.
    bridge.answer(prompt, AgentDecision.deny);
    await tester.pumpAndSettle();
    expect(await answer, AgentDecision.deny);
    expect(find.text('Allow'), findsNothing);
  });
}
