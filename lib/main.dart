import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/routes.dart';

/// Opens the app at any route, e.g. `--dart-define=START=/vault`.
const String _start = String.fromEnvironment(
  'START',
  defaultValue: Routes.unlock,
);

void main() => runApp(const DevVaultApp(initialLocation: _start));
