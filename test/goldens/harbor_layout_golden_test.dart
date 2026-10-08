@Tags(['golden'])
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harbor/harbor.dart';
import 'package:harbor_test/harbor_test.dart';
import 'package:rubric/app/app.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/features/home/home_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/db.dart';

/// Every place Rubric's layout must keep clear of something (the status bar,
/// the home indicator, a notch, the keyboard, our own docked CTA and nav
/// bar), drawn on real device geometry with harbor's chart over the real UI:
/// teal is a pier (content runs under it), sand is a quay (content ends at
/// it), blue is the keyboard, and the outline is the clear water left over.
/// A golden is right when nothing that should be readable or tappable sits
/// under teal, sand or blue.
///
/// Baselines are made only by the "Golden baselines" workflow on a pinned
/// Linux image (see flutter_test_config.dart). `tool/golden_preview.sh`
/// renders them locally to look at.

const _cta = Key('cta');
const _field = Key('field');

/// Harbor's chart over the whole screen, so the regions being kept clear of
/// are in the picture, not just the result.
/// Its labels (each dock's name and height) get the app's own font, which
/// the test loaded; harbor otherwise draws them in the test font's boxes.
Widget _charted(Widget app) => RepaintBoundary(
  child: HarborChartOverlay(
    labelStyle: const TextStyle(fontFamily: 'Avenir-Heavy'),
    child: app,
  ),
);

Widget _app(Widget home) => _charted(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildRubricTheme(),
    builder: (context, child) => HarborSea(child: child!),
    home: home,
  ),
);

/// A page like Rubric's list pages: rows of cards, a docked orange CTA.
Widget _page({
  double ctaHeight = Sizes.ctaHeight,
  bool withField = false,
  int rows = 12,
}) => RubricPage(
  title: 'Biology · Period 5',
  showBack: false,
  bottomCta: SizedBox(
    key: _cta,
    height: ctaHeight,
    child: ctaHeight > Sizes.ctaHeight
        ? const _TallTray()
        : AccentButton(label: 'Add student', onTap: () {}),
  ),
  children: [
    for (var i = 1; i <= rows; i++) ...[
      _Row(i),
      const SizedBox(height: Insets.sm),
    ],
    if (withField)
      const TextField(
        key: _field,
        decoration: InputDecoration(hintText: 'The last field on the page'),
      ),
  ],
);

class _Row extends StatelessWidget {
  const new(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: Insets.md),
    decoration: BoxDecoration(color: primaryCard, borderRadius: Corners.card),
    alignment: AlignmentDirectional.centerStart,
    child: Text('Student $n', style: RubricTextStyles.bodySmall),
  );
}

/// Stands in for the rubric builder's ungrouped tray: a docked CTA much
/// taller than a button, which is why the page can't reserve a fixed height.
class _TallTray extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: Insets.sm),
    decoration: BoxDecoration(color: primaryDark, borderRadius: Corners.card),
    alignment: Alignment.center,
    child: const Text(
      '3 ungrouped objectives',
      style: RubricTextStyles.bodySmall,
    ),
  );
}

/// The chart animates, so frames are pumped rather than settled.
Future<void> _frames(WidgetTester tester, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
  await _frames(tester);
}

String _slug(HarborTrialDevice d) =>
    d.name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');

Future<void> _golden(
  WidgetTester tester,
  String scene,
  HarborTrialDevice d,
) async {
  await _expectRealFonts(tester);
  await expectLater(
    find.byType(RepaintBoundary).first,
    matchesGoldenFile('goldens/$scene.${_slug(d)}.png'),
  );
}

/// The font families the app bundles, read once from its font manifest.
late final Set<String> _shipped;

/// Every piece of text on screen is drawn in a font the app ships (its font
/// manifest, which flutter_test_config.dart loads), never the test font. A
/// style with no family, or a family the app doesn't bundle, falls back to
/// the test font and draws boxes, and the golden would quietly bake them in.
Future<void> _expectRealFonts(WidgetTester tester) async {
  final strays = <String>[];
  for (final paragraph
      in tester.allRenderObjects.whereType<RenderParagraph>()) {
    paragraph.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.trim().isNotEmpty ?? false)) {
        final family = span.style?.fontFamily;
        if (family == null || !_shipped.contains(family)) {
          strays.add('"${span.text}" in ${family ?? 'no family'}');
        }
      }
      return true;
    });
  }
  // Positive control: the screen has text at all, so "no strays" means
  // something.
  expect(
    tester.allRenderObjects.whereType<RenderParagraph>(),
    isNotEmpty,
    reason: 'no text on screen to check',
  );
  expect(strays, isEmpty, reason: 'text not in a font the app ships');
}

/// Rubric itself, onboarded, on an empty database: the shell and Home.
Future<HarborSeaTrial> _pumpRubric(
  WidgetTester tester,
  HarborTrialDevice device,
) async {
  SharedPreferences.setMockInitialValues({
    'settings.v1': '{"onboardingComplete":true}',
  });
  final prefs = await SharedPreferences.getInstance();
  final db = testDatabase();
  addTearDown(db.close);
  final trial = await tester.pumpSeaTrial(
    _charted(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          // A fixed morning, so the greeting never depends on when CI runs.
          homeClockProvider.overrideWithValue(
            () => DateTime(2026, 10, 5, 9, 41),
          ),
        ],
        child: const RubricApp(),
      ),
    ),
    device: device,
  );
  await _frames(tester, 30);
  return trial;
}

/// Unmounts the app so drift's stream-teardown timers fire inside the test.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

const List<HarborTrialDevice> _phones = [
  HarborTrialDevice.iPhone17,
  HarborTrialDevice.iPhoneSE,
  HarborTrialDevice.androidThreeButton,
  HarborTrialDevice.androidGesture,
];

void main() {
  // Real I/O, so outside the tests' fake-async zone.
  setUpAll(() async {
    final manifest = jsonDecode(
      await rootBundle.loadString('FontManifest.json'),
    ) as List<Object?>;
    _shipped = {
      for (final entry in manifest.cast<Map<String, Object?>>())
        entry['family']! as String,
    };
  });

  group('a page with a docked CTA, scrolled to the end', () {
    for (final device in [..._phones, HarborTrialDevice.iPhone17Landscape]) {
      // The last row rests above the CTA, the CTA above the home indicator
      // (or the Android nav bar), and in landscape the rows clear the notch.
      testWidgets(device.name, (tester) async {
        await tester.pumpSeaTrial(_app(_page()), device: device);
        await _scrollToEnd(tester);
        await _golden(tester, 'page_cta_end', device);
      });
    }
  });

  testWidgets('a docked CTA much taller than a button', (tester) async {
    // The old page reserved 130pt whatever the CTA's height, so rows went
    // under a tray like this one; now the last row rests above it.
    const device = HarborTrialDevice.iPhone17;
    await tester.pumpSeaTrial(_app(_page(ctaHeight: 300)));
    await _scrollToEnd(tester);
    await _golden(tester, 'page_tall_cta_end', device);
  });

  group('typing in the last field on the page', () {
    for (final device in [
      HarborTrialDevice.iPhone17,
      HarborTrialDevice.androidThreeButton,
    ]) {
      // The keyboard (blue) rises; the CTA floats on it, and the field being
      // typed in stays visible above both.
      testWidgets(device.name, (tester) async {
        final trial = await tester.pumpSeaTrial(
          _app(_page(withField: true)),
          device: device,
        );
        await _scrollToEnd(tester);
        await tester.tap(find.byKey(_field));
        await trial.raiseTide();
        await _frames(tester);
        await _golden(tester, 'page_field_keyboard', device);
      });
    }
  });

  group('a sheet', () {
    Widget opener() => _app(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: AccentButton(
              label: 'Add a student',
              onTap: () => showRubricSheet<void>(
                context: context,
                child: const RubricSheet(
                  title: 'Add a student',
                  child: RubricFormWell(
                    child: TextField(
                      decoration: InputDecoration(hintText: 'First name'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (final device in [
      HarborTrialDevice.iPhone17,
      HarborTrialDevice.iPhoneSE,
    ]) {
      // Keyboard down: the sheet floats 12pt above the home indicator (it
      // used to sit inside it). Keyboard up: 12pt above the keyboard.
      testWidgets('${device.name}, keyboard down then up', (tester) async {
        final trial = await tester.pumpSeaTrial(opener(), device: device);
        await tester.tap(find.text('Add a student'));
        await _frames(tester);
        await _golden(tester, 'sheet_keyboard_down', device);

        await tester.tap(find.byType(TextField));
        await trial.raiseTide();
        await _frames(tester);
        await _golden(tester, 'sheet_keyboard_up', device);
      });
    }
  });

  group('the shell', () {
    for (final device in [
      HarborTrialDevice.iPhone17,
      HarborTrialDevice.androidThreeButton,
      // Wide enough for the rail, with the notch on its side.
      HarborTrialDevice.iPhone17Landscape,
      HarborTrialDevice.foldableOpen,
    ]) {
      // Phones: the nav bar is a quay, its colour running under the home
      // indicator. Wide: the rail is a quay at its own width, and Home gets
      // the rest of the screen.
      testWidgets(device.name, (tester) async {
        await _pumpRubric(tester, device);
        await _golden(tester, 'shell_home', device);
        await _unmount(tester);
      });
    }
  });
}
