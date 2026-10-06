import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Width, height and whether a PNG can carry transparency, read from its
/// IHDR header (bytes 16-25): colour types 4 and 6 have an alpha channel.
({int width, int height, bool alpha}) _png(String path) {
  final bytes = File(path).readAsBytesSync();
  final header = ByteData.sublistView(bytes, 16, 26);
  final colorType = header.getUint8(9);
  return (
    width: header.getUint32(0),
    height: header.getUint32(4),
    alpha: colorType == 4 || colorType == 6,
  );
}

/// The launcher icons are generated from assets/icon/ by
/// flutter_launcher_icons (flutter_launcher_icons.yaml). These tests hold the
/// generated set complete, so a regeneration or a template reset that drops a
/// size fails here rather than on a home screen or in App Store review.
void main() {
  group('iOS', () {
    const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final images =
        (jsonDecode(File('$dir/Contents.json').readAsStringSync())
                as Map<String, Object?>)['images']!
            as List<Object?>;

    test('every slot names a file of the size it declares', () {
      expect(images, hasLength(greaterThan(10)));
      for (final image in images.cast<Map<String, Object?>>()) {
        final file = image['filename'] as String?;
        expect(file, isNotNull, reason: '$image has no file');
        final points = double.parse((image['size']! as String).split('x')[0]);
        final scale = int.parse(
          (image['scale']! as String).replaceAll('x', ''),
        );
        final png = _png('$dir/$file');
        expect(png.width, (points * scale).round(), reason: file);
        expect(png.height, png.width, reason: file);
      }
    });

    test('the App Store icon is 1024 px and opaque', () {
      // App Store Connect rejects an app icon with an alpha channel.
      final marketing = images.cast<Map<String, Object?>>().singleWhere(
        (i) => i['idiom'] == 'ios-marketing',
      );
      final png = _png('$dir/${marketing['filename']}');
      expect(png.width, 1024);
      expect(png.alpha, isFalse);
    });
  });

  group('Android', () {
    const res = 'android/app/src/main/res';
    const densities = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };

    test('the legacy icon exists at every density', () {
      for (final MapEntry(key: density, value: px) in densities.entries) {
        final png = _png('$res/mipmap-$density/ic_launcher.png');
        expect((png.width, png.height), (px, px), reason: density);
      }
    });

    test('the adaptive icon has its background, foreground and monochrome', () {
      final adaptive = File('$res/mipmap-anydpi-v26/ic_launcher.xml')
          .readAsStringSync();
      expect(adaptive, contains('@color/ic_launcher_background'));
      expect(adaptive, contains('@drawable/ic_launcher_foreground'));
      expect(adaptive, contains('@drawable/ic_launcher_monochrome'));
      expect(
        File('$res/values/colors.xml').readAsStringSync(),
        contains('name="ic_launcher_background"'),
      );
      for (final MapEntry(key: density, value: px) in densities.entries) {
        // Adaptive layers are 108 dp against the legacy icon's 48 dp.
        final layer = px * 108 ~/ 48;
        for (final name in [
          'ic_launcher_foreground',
          'ic_launcher_monochrome',
        ]) {
          final png = _png('$res/drawable-$density/$name.png');
          expect(png.width, layer, reason: '$density $name');
          expect(png.alpha, isTrue, reason: '$density $name is a layer');
        }
      }
    });

    test('the manifest uses the icon', () {
      expect(
        File('$res/../AndroidManifest.xml').readAsStringSync(),
        contains('android:icon="@mipmap/ic_launcher"'),
      );
    });
  });
}
