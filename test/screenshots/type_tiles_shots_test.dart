/// M0-06: every type's tile, dark and light, next to its label. See
/// harness.dart for how goldens are generated and checked.
@Tags(['golden'])
library;

import 'package:devvault/shared/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import '../pump_bc.dart';

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness == Brightness.dark
        ? 'M0-type-tiles'
        : 'M0-type-tiles-light';
    testWidgets(name, (tester) async {
      tester.view
        ..physicalSize = const Size(720, 400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      try {
        await pumpBC(
          tester,
          RepaintBoundary(
            key: const ValueKey('tiles'),
            child: Builder(
              builder: (context) => ColoredBox(
                color: context.bcTheme.background,
                child: Padding(
                  padding: const EdgeInsets.all(BCSpacing.lg),
                  child: Wrap(
                    spacing: BCSpacing.md,
                    runSpacing: BCSpacing.md,
                    children: [
                      for (final type in ItemType.values)
                        SizedBox(
                          width: 150,
                          child: Row(
                            spacing: BCSpacing.sm,
                            children: [
                              TypeIconTile(type: type),
                              Expanded(
                                child: BCText(
                                  type.label,
                                  type: BCTextType.bodySm,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          brightness: brightness,
        );
        await expectLater(
          find.byKey(const ValueKey('tiles')),
          matchesGoldenFile('../../screenshots/$name.png'),
        );
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
