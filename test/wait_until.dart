import 'package:flutter_test/flutter_test.dart';

/// Polls [condition] (real time) until it holds, or fails after [within].
Future<void> until(
  bool Function() condition, {
  Duration within = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(within);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for a condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
