import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release builds may use the network (sync needs it)', () {
    // Only src/main reaches a release build; the debug and profile manifests
    // grant INTERNET for hot reload and so hide its absence in development.
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
    );
  });
}
