import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/main.dart';

void main() {
  test('a release build talks to production, never localhost', () {
    final url = serverUrl(release: true);
    expect(url.toString(), productionServer);
    expect(url.scheme, 'https');
  });

  // Tests run as a debug build, so the default is the debug path.
  test('a debug build talks to the local server', () {
    expect(serverUrl().toString(), 'http://localhost:8792');
    expect(
      serverUrl(platform: TargetPlatform.android).toString(),
      'http://10.0.2.2:8792',
    );
  });
}
