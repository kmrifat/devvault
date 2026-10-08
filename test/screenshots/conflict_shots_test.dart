@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import '../test_overrides.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  /// Puts "Upload keystore" in conflict with a version from another device
  /// and opens the sheet (design frame N05).
  Future<void> openConflict(WidgetTester tester) async {
    final container = appContainer(tester);
    final session = container.read(vaultSessionProvider) as Unlocked;
    final mine = session.index.all.firstWhere(
      (i) => i.title == 'Upload keystore',
    );
    const other = '00000000-0000-4000-8000-0000000000ff';
    final theirs = Item.fromJson({
      ...mine
          .copyWith(
            title: 'Play upload keystore',
            fields: {
              ...mine.fields,
              'key_password': const ItemField(
                value: 'changed-elsewhere',
                source: FieldSource.user,
                secret: true,
              ),
            },
          )
          .toJson(),
      'rev': Hlc.zero(other).tick(DateTime.utc(2026, 10, 7, 10)).toString(),
      'device_id': other,
      'updated_at': '2026-10-07T10:00:00Z',
    });
    await tester.runAsync(
      () => container
          .read(vaultSessionProvider.notifier)
          .saveItem(withConflict(mine, Conflict()..addVersion(theirs))),
    );
    GoRouter.of(tester.element(find.byType(VaultListPane)))
        .go(Routes.vault(item: mine.id));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolve…'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Name from the other device'));
  }

  shot('N05-conflict', Routes.vault(), sample: true, interact: openConflict);
  shot(
    'N05-conflict-light',
    Routes.vault(),
    sample: true,
    interact: openConflict,
    brightness: Brightness.light,
  );
}
