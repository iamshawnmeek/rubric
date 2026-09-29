import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/features/settings/app_info.dart';

void main() {
  test('appVersion matches the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    expect(version, isNotNull);
    expect(appVersion, version);
  });
}
