import 'dart:async';

import 'package:app_deploy_screenshots/app_deploy_screenshots.dart';

/// Loads the app's fonts (Avenir from pubspec) so the store images render
/// real type, not the test font's boxes. Scoped to this folder: only the
/// store-screenshot test pays for it.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Rubric needs no platform-channel stubs (its tests mock prefs
  // themselves); explicit, because the default flips in 2.0.
  await AppDeployScreenshots.initialize(mockPlatformChannels: false);
  await testMain();
}
