// M0-07: the real main(), with every real service, boots on this platform
// to the lock screens: create on a fresh device, unlock where a vault
// already exists.
//
//   flutter test integration_test/app_boot_test.dart -d <device>
//
// It uses the platform's real app support folder; it reads and creates
// nothing there but the device id and settings files.
import 'package:devvault/app/routes.dart';
import 'package:devvault/features/create_vault/create_vault_screen.dart';
import 'package:devvault/features/unlock/unlock_screen.dart';
import 'package:devvault/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('main() boots to create on a fresh device, else unlock', (
    tester,
  ) async {
    await app.main();
    final lockScreen = find.byWidgetPredicate(
      (w) => w is CreateVaultScreen || w is UnlockScreen,
    );
    for (var i = 0; i < 100 && lockScreen.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(lockScreen, findsOneWidget);

    final path = GoRouter.of(tester.element(lockScreen)).state.uri.path;
    expect(path, anyOf(Routes.create, Routes.unlock));
    expect(
      path == Routes.unlock,
      find.byType(UnlockScreen).evaluate().isNotEmpty,
    );
    // ignore: avoid_print
    print('BOOTED TO $path');
  });
}
