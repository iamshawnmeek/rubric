import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_deploy_screenshots/app_deploy_screenshots.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden baselines come from one place: the "Golden baselines" GitHub
/// workflow (.github/workflows/goldens.yaml), on a pinned Ubuntu image and
/// the Flutter version in .fvmrc, so every pixel is rendered by the same
/// engine, fonts and OS. A baseline written anywhere else (a Mac renders text
/// a little differently) would make every later comparison flaky, so:
///
/// - `--update-goldens` is refused unless RUBRIC_GOLDEN_BASELINE=ci is set,
///   which only that workflow does.
/// - RUBRIC_GOLDEN_PREVIEW=1 renders every golden to build/golden_preview/
///   instead, to look at locally. Nothing there is compared or committed.
///   `tool/golden_preview.sh` runs it.
/// - Comparing against the baselines is Linux-only, and in CI (ci.yaml's
///   goldens job, same pinned image).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Real type: Avenir, Material icons and Font Awesome from the app's font
  // manifest. A font that fails to load fails the run; a golden in the test
  // font's boxes would pass and show nothing.
  await AppDeployScreenshots.loadAppFonts(skipOnError: false);

  final env = Platform.environment;
  if (env['RUBRIC_GOLDEN_PREVIEW'] == '1') {
    goldenFileComparator = _PreviewComparator(
      Uri.directory('${Directory.current.path}/build/golden_preview/'),
    );
  } else if (autoUpdateGoldenFiles && env['RUBRIC_GOLDEN_BASELINE'] != 'ci') {
    throw StateError(
      'Golden baselines are made by the "Golden baselines" GitHub workflow, '
      'on a pinned Linux image, never locally. To look at the goldens, run '
      'tool/golden_preview.sh (writes build/golden_preview/).',
    );
  }
  await testMain();
}

/// Writes each golden as an image and passes: a preview, not a comparison.
final class _PreviewComparator extends GoldenFileComparator {
  new(this.root);

  final Uri root;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    await update(golden, imageBytes);
    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    final file = File.fromUri(root.resolveUri(golden));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(imageBytes, flush: true);
  }
}
