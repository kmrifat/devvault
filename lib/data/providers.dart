import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// Every service the app depends on, in one place. Values that need I/O are
// loaded in main() before the first frame and handed in with overrides, so
// providers stay synchronous. Tests override the same providers with fakes
// (see test/test_overrides.dart).

/// The current time. Overridden with a fixed clock in tests, so expiry
/// rules and notification plans are deterministic.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The app support folder: vaults, device id and sync state live here.
final appSupportDirProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// This device's id, stamped on every record it writes.
final deviceIdProvider = Provider<String>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);
