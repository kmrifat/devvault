import 'package:devvault/shared/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import 'pump_bc.dart';

void main() {
  group('TypeIconTile', () {
    for (final brightness in Brightness.values) {
      testWidgets('renders every type in ${brightness.name}', (tester) async {
        await pumpBC(
          tester,
          Wrap(
            children: [
              for (final type in ItemType.values) TypeIconTile(type: type),
            ],
          ),
          brightness: brightness,
        );
        for (final type in ItemType.values) {
          expect(find.bySemanticsLabel(type.label), findsOneWidget);
          expect(find.byIcon(TypeIconTile.iconFor(type)), findsOneWidget);
        }
      });
    }

    test('each file type has its own icon', () {
      final fileTypes = ItemType.values.where(
        (t) => t != ItemType.gcpServiceAccount && t != ItemType.genericSecret,
      );
      final icons = fileTypes.map(TypeIconTile.iconFor).toSet();
      expect(icons, hasLength(fileTypes.length));
    });
  });

  group('MonoText', () {
    const style = TextStyle(fontSize: 14);
    const fingerprint =
        'FA:C6:17:45:DC:09:03:78:6F:B9:ED:E6:2A:96:2B:39:9F:73:48:F0';

    String fit(double width) => MonoText.fitMiddle(
      fingerprint,
      style,
      width,
      TextScaler.noScaling,
      TextDirection.ltr,
    );

    test('leaves text that fits alone', () {
      expect(fit(10000), fingerprint);
      expect(fit(double.infinity), fingerprint);
    });

    test('keeps both ends and drops the middle when too wide', () {
      final short = fit(200);
      expect(short, contains(MonoText.ellipsis));
      final [head, tail] = short.split(MonoText.ellipsis);
      expect(fingerprint, startsWith(head));
      expect(fingerprint, endsWith(tail));
      expect((head.length - tail.length).abs(), lessThanOrEqualTo(1));
    });

    testWidgets('shows the shortened form in a narrow box', (tester) async {
      await pumpBC(
        tester,
        const SizedBox(
          width: 160,
          child: MonoText(fingerprint, middleEllipsis: true),
        ),
      );
      final shown = tester.widget<Text>(find.byType(Text)).data!;
      expect(shown, contains(MonoText.ellipsis));
      expect(shown, startsWith('FA:C6'));
      expect(shown, endsWith('F0'));
    });
  });

  group('ProvenanceLabel', () {
    test('names the source of every expiry, or says it is unknown', () {
      expect(
        ProvenanceLabel.textFor(ExpirySource.file, fileKind: 'certificate'),
        'From certificate',
      );
      expect(ProvenanceLabel.textFor(ExpirySource.file), 'From file');
      expect(ProvenanceLabel.textFor(ExpirySource.user), 'Set by you');
      expect(ProvenanceLabel.textFor(null), 'Expiry unknown');
    });

    testWidgets('renders as a chip', (tester) async {
      await pumpBC(tester, const ProvenanceLabel(source: ExpirySource.user));
      expect(find.text('Set by you'), findsOneWidget);
    });
  });

  group('SecretRow', () {
    const secret = 'hunter2-store-pass';

    testWidgets('is masked until revealed', (tester) async {
      await pumpBC(
        tester,
        const SizedBox(
          width: 400,
          child: SecretRow(label: 'Store password', secret: secret),
        ),
      );
      expect(find.text(secret), findsNothing);
      expect(find.text(SecretRow.mask), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Reveal'));
      await tester.pump();
      expect(find.text(secret), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Hide'));
      await tester.pumpAndSettle();
      expect(find.text(secret), findsNothing);
    });

    testWidgets('copy hands the secret to the caller', (tester) async {
      String? copied;
      await pumpBC(
        tester,
        SizedBox(
          width: 400,
          child: SecretRow(
            label: 'Store password',
            secret: secret,
            onCopy: (value) => copied = value,
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Copy'));
      await tester.pumpAndSettle();
      expect(copied, secret);
      expect(find.text(secret), findsNothing, reason: 'copy does not reveal');
    });

    testWidgets('has no copy button without a handler', (tester) async {
      await pumpBC(
        tester,
        const SizedBox(
          width: 400,
          child: SecretRow(label: 'Key password', secret: secret),
        ),
      );
      expect(find.bySemanticsLabel('Copy'), findsNothing);
    });
  });

  group('showConfirmDialog', () {
    Future<Future<bool>> open(WidgetTester tester) async {
      late Future<bool> result;
      await pumpBC(
        tester,
        Builder(
          builder: (context) => BCButton(
            onPressed: () => result = showConfirmDialog(
              context,
              title: 'Delete item?',
              message: 'A tombstone is synced to your other devices.',
              confirmLabel: 'Delete',
              destructive: true,
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('confirm resolves true', (tester) async {
      final result = await open(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('cancel resolves false', (tester) async {
      final result = await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });
}
