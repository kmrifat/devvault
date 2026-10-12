import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/search_match.dart';
import 'package:devvault/data/search_query.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

const _appId = '00000000-0000-4000-8000-000000000001';
const _device = '00000000-0000-4000-8000-000000000003';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> open(WidgetTester tester, [String? location]) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 2400 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: location ?? Routes.search(),
      vault: TestVault.sample,
      layout: AppLayout.mobile,
    );
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(SearchScreen))).state.uri
          .toString();

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  Finder onScreen(String text) =>
      find.descendant(of: find.byType(SearchScreen), matching: find.text(text));

  testWidgets('Search is the fourth tab', (tester) async {
    await open(tester, Routes.vault());
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(location(tester), Routes.search());
  });

  testWidgets('browse lists what the vault holds, with counts', (tester) async {
    await open(tester);
    expect(onScreen('TYPES'), findsOneWidget);
    expect(onScreen('Keystores'), findsOneWidget);
    expect(onScreen('Kitchenly'), findsOneWidget);
    expect(onScreen('Ledgerly'), findsOneWidget);
    expect(onScreen('android'), findsOneWidget);
    expect(onScreen('#release'), findsOneWidget);
    // Nothing that isn't in the vault.
    expect(onScreen('SSH keys'), findsNothing);
  });

  testWidgets('typing lists matches and says which field matched', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchScreen),
        matching: find.byType(EditableText),
      ),
      'com.kitchenly.android',
    );
    await tester.pumpAndSettle();
    expect(location(tester), Routes.search(q: 'com.kitchenly.android'));
    expect(onScreen('TYPES'), findsNothing);
    expect(onScreen('Upload keystore'), findsOneWidget);
    expect(onScreen('Package'), findsWidgets);
    // An item of another app doesn't match.
    expect(onScreen('Stripe secret key'), findsNothing);
  });

  testWidgets('a type from browse scopes the results, removably', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(onScreen('Keystores'));
    await tester.pumpAndSettle();
    expect(
      location(tester),
      Routes.search(type: ItemType.androidKeystore.wireName),
    );
    expect(onScreen('1 RESULT'), findsOneWidget);
    expect(onScreen('Upload keystore'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Remove filter Keystores'));
    await tester.pumpAndSettle();
    expect(location(tester), Routes.search());
    expect(onScreen('TYPES'), findsOneWidget);
  });

  testWidgets('no matches says what search covers', (tester) async {
    await open(tester, Routes.search(q: 'zz-nothing'));
    expect(onScreen('No matches'), findsOneWidget);
    expect(onScreen('Secret values are never searched'), findsOneWidget);
  });

  testWidgets('a secret value is never found', (tester) async {
    await open(tester, Routes.search(q: 'sk_live_sample'));
    expect(onScreen('No matches'), findsOneWidget);
  });

  testWidgets('tapping a result pushes the item', (tester) async {
    await open(tester, Routes.search(q: 'upload'));
    final keystore = index(tester).all
        .firstWhere((i) => i.title == 'Upload keystore');
    await tester.tap(onScreen('Upload keystore'));
    await tester.pumpAndSettle();
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri
          .toString(),
      Routes.item(keystore.id),
    );
  });

  group('SearchMatch', () {
    final app = AppRecord(
      id: _appId,
      name: 'Kitchenly',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      rev: Hlc(0, 0, _device),
      deviceId: _device,
      bundleIds: const ['com.kitchenly.app'],
    );
    Item item({
      String title = 'APNs key',
      Map<String, ItemField> fields = const {},
    }) => Item(
      id: '00000000-0000-4000-8000-000000000002',
      typeName: ItemType.appleAuthKey.wireName,
      title: title,
      appId: _appId,
      fields: fields,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      rev: Hlc(0, 0, _device),
      deviceId: _device,
    );

    test('names the field and the matched characters', () {
      final match = SearchMatch.of(item(), app, 'kitchen')!;
      expect(match.label, 'App');
      final id = SearchMatch.of(item(), app, 'com.kitch')!;
      expect(id.label, 'Bundle ID');
      expect(id.value.substring(id.start!, id.end), 'com.kitch');
      expect(id.mono, isTrue);
    });

    test('a word in the title needs no explanation', () {
      expect(SearchMatch.of(item(), app, 'apns'), isNull);
      expect(SearchMatch.of(item(), app, ''), isNull);
    });

    test('a fingerprint matches without its colons', () {
      final match = SearchMatch.of(
        item(
          fields: {
            'sha1': const ItemField(
              value: '5E:8F:16:06',
              source: FieldSource.file,
            ),
          },
        ),
        app,
        '5e8f16',
      )!;
      expect(match.label, 'SHA-1');
      expect(match.start, isNull);
    });

    test('never a secret field', () {
      final match = SearchMatch.of(
        item(
          fields: {
            'key_password': const ItemField(
              value: 'hunter2',
              source: FieldSource.user,
              secret: true,
            ),
          },
        ),
        app,
        'hunter2',
      );
      expect(match, isNull);
    });
  });

  test('search links carry only what is set', () {
    expect(Routes.search(), '/search');
    expect(Routes.search(q: 'a b', tag: 'ci'), '/search?q=a+b&tag=ci');
    final query = SearchQuery.fromUri(Uri.parse('/search?q=%20&app=a1'));
    expect(query.q, isNull);
    expect(query.isScoped, isTrue);
    expect(query.unscoped.location(), '/search');
  });
}
