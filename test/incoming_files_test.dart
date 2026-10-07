import 'dart:async';
import 'dart:io';

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/import/import_dialog.dart';
import 'package:devvault/services/incoming_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_overrides.dart';

/// Stands in for the platform channel: tests drop paths in [waiting].
class FakeIncomingFiles implements IncomingFiles {
  final waiting = <String>[];
  final _available = StreamController<void>.broadcast();

  void arrive(String path) {
    waiting.add(path);
    _available.add(null);
  }

  @override
  Stream<void> get available => _available.stream;

  @override
  Future<List<String>> take() async {
    final taken = [...waiting];
    waiting.clear();
    return taken;
  }
}

void main() {
  setUpAll(loadTestCrypto);

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('incoming_test_'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// A file as the native side leaves it: alone in its own folder.
  String received(String name, String text) {
    final dir = Directory('${temp.path}/devvault-incoming-${name.hashCode}')
      ..createSync();
    return (File('${dir.path}/$name')..writeAsStringSync(text)).path;
  }

  test('reading a received file removes its temporary folder', () async {
    final path = received('AuthKey_ABCDE12345.p8', 'key');
    final file = await readIncoming(path);
    expect(file!.name, 'AuthKey_ABCDE12345.p8');
    expect(String.fromCharCodes(file.bytes), 'key');
    expect(temp.listSync(), isEmpty);
    expect(await readIncoming(path), isNull);
  });

  testWidgets('a file that arrives while locked waits for unlock', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final incoming = FakeIncomingFiles()
      ..arrive(received('google-services.json', '{"project_info":{}}'));
    final dir = (await tester.runAsync(
      () => testSupportDir(TestVault.locked),
    ))!;
    await tester.pumpWidget(
      testApp(
        location: Routes.unlock,
        supportDir: dir,
        layout: AppLayout.mobile,
        overrides: [incomingFilesProvider.overrideWithValue(incoming)],
      ),
    );
    await tester.pumpAndSettle();
    // Locked: no import yet, and the file is still waiting in DevVault.
    expect(find.byType(ImportDialog), findsNothing);
    expect(temp.listSync(), hasLength(1));

    await tester.runAsync(
      () =>
          appContainer(tester)
              .read(vaultSessionProvider.notifier)
              .unlock(testPassword),
    );
    // Real file I/O and parsing: poll on the wall clock, which can be slow
    // when the whole suite runs at once.
    final waited = Stopwatch()..start();
    while (find.byType(ImportDialog).evaluate().isEmpty &&
        waited.elapsed < const Duration(seconds: 20)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byType(ImportDialog), findsOneWidget);
    expect(find.text('google-services.json'), findsWidgets);
    expect(temp.listSync(), isEmpty);
  });

  test('desktop and tests get nothing', () async {
    expect(await const NoIncomingFiles().take(), isEmpty);
  });
}
