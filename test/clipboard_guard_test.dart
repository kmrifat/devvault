import 'package:devvault/services/clipboard_guard.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeClipboard implements ClipboardAccess {
  String? text;

  @override
  Future<String?> read() async => text;

  @override
  Future<void> write(String value) async => text = value;
}

void main() {
  late FakeClipboard clipboard;
  late ClipboardGuard guard;

  setUp(() {
    clipboard = FakeClipboard();
    guard = ClipboardGuard(clipboard: clipboard);
  });
  tearDown(() => guard.dispose());

  testWidgets('clears the secret after 30 seconds', (tester) async {
    await guard.copySecret('hunter2');
    expect(clipboard.text, 'hunter2');
    await tester.pump(const Duration(seconds: 29));
    expect(clipboard.text, 'hunter2');
    await tester.pump(const Duration(seconds: 1));
    expect(clipboard.text, '');
    expect(guard.isHoldingSecret, isFalse);
  });

  testWidgets('leaves something the user copied since alone', (tester) async {
    await guard.copySecret('hunter2');
    await clipboard.write('my own note');
    await tester.pump(const Duration(seconds: 30));
    expect(clipboard.text, 'my own note');
  });

  testWidgets('copying again restarts the countdown', (tester) async {
    await guard.copySecret('first');
    await tester.pump(const Duration(seconds: 20));
    await guard.copySecret('second');
    await tester.pump(const Duration(seconds: 20));
    expect(clipboard.text, 'second', reason: 'only 20 s since the copy');
    await tester.pump(const Duration(seconds: 10));
    expect(clipboard.text, '');
  });

  testWidgets('clearNow empties it at once (lock, quit)', (tester) async {
    await guard.copySecret('hunter2');
    await guard.clearNow();
    expect(clipboard.text, '');
    clipboard.text = 'later copy';
    await guard.clearNow();
    expect(clipboard.text, 'later copy', reason: 'nothing of ours left');
  });

  test('a pasted secret is taken off the clipboard (B4b)', () async {
    expect(await guard.takePasted(), isNull, reason: 'nothing to paste');
    clipboard.text = 'sk_live_from_elsewhere';
    expect(await guard.takePasted(), 'sk_live_from_elsewhere');
    expect(clipboard.text, '');
    expect(await guard.takePasted(), isNull);
  });

  testWidgets('marks the copy as a secret where the clipboard can', (
    tester,
  ) async {
    final secret = _SecretClipboard();
    final guard = ClipboardGuard(
      clipboard: secret,
      clearAfter: const Duration(seconds: 10),
    );
    addTearDown(guard.dispose);
    await guard.copySecret('hunter2');
    expect(secret.text, 'hunter2');
    expect(secret.expiresIn, const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(secret.text, '', reason: 'still cleared by DevVault itself');
  });
}

class _SecretClipboard extends FakeClipboard implements SecretClipboardAccess {
  Duration? expiresIn;

  @override
  Future<void> writeSecret(String text, {required Duration expiresIn}) async {
    this.text = text;
    this.expiresIn = expiresIn;
  }
}
