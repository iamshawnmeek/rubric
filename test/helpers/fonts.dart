import 'dart:io';

import 'package:flutter/services.dart';

var _loaded = false;

/// Loads the real Avenir faces so layout tests measure real text. Without it
/// every glyph renders in the square test font, which wraps far more than
/// Avenir and makes any "does this fit" assertion meaningless.
Future<void> loadAppFonts() async {
  if (_loaded) return;
  for (final face in const ['Black', 'Heavy', 'Light']) {
    final bytes = File('assets/custom_fonts/Avenir-$face.ttf')
        .readAsBytesSync();
    final loader = FontLoader('Avenir-$face')
      ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
    await loader.load();
  }
  _loaded = true;
}
