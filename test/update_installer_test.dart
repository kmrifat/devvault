import 'package:devvault/services/update_installer.dart';
import 'package:devvault/services/updates.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('devvault/updater');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final release = Release(version: const AppVersion(1, 2, 0));

  late List<String> calls;
  void answer(Object? Function(MethodCall call) handler) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return handler(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('none without the channel (Linux, the Windows zip)', () async {
    expect(await ChannelUpdateInstaller.load(), isNull);
  });

  test('none when the build has no update key', () async {
    answer((_) => false);
    expect(await ChannelUpdateInstaller.load(), isNull);
    expect(calls, ['isAvailable']);
  });

  test('installs through the OS updater', () async {
    answer((_) => true);
    final installer = await ChannelUpdateInstaller.load();
    expect(installer, isNotNull);
    answer((_) => null);
    await installer!.install(release);
    expect(calls, ['install']);
  });

  test('says so when the updater can’t start', () async {
    answer((_) => true);
    final installer = (await ChannelUpdateInstaller.load())!;
    answer(
      (_) => throw PlatformException(
        code: 'unavailable',
        message: 'This build can’t update itself.',
      ),
    );
    await expectLater(
      installer.install(release),
      throwsA(
        isA<UpdateCheckFailed>().having(
          (e) => e.reason,
          'reason',
          'This build can’t update itself.',
        ),
      ),
    );
  });
}
