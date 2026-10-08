// Compiled to a native executable by fixed_random_guard_test.dart, so it runs
// in product mode the way a release build does.
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'package:vault_core/vault_core.dart';

Future<void> main() async {
  try {
    await VaultCrypto.withFixedRandom(const [1, 2, 3]);
    print('allowed');
  } on StateError {
    print('refused');
  }
}
