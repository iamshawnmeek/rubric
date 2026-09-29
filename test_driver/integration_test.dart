import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves every `binding.takeScreenshot(name)` to `build/screens/<name>.png` so a
/// person (or the owner agent) can review the real rendering.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/screens/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
