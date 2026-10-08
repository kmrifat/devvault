import 'dart:io';

import 'package:test/test.dart';

/// P0-02: deterministic randomness exists for test vectors only. A release
/// build is AOT-compiled in product mode, where withFixedRandom must refuse.
void main() {
  test('withFixedRandom refuses to run in a product-mode build', () async {
    final out = Directory.systemTemp.createTempSync('fixed_random_');
    addTearDown(() => out.deleteSync(recursive: true));
    final exe = '${out.path}/probe${Platform.isWindows ? '.exe' : ''}';
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'test/product_mode/fixed_random_probe.dart',
      '-o',
      exe,
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');

    final run = await Process.run(exe, const []);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    expect((run.stdout as String).trim(), 'refused');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
