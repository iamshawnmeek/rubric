// The whole App Store and Google Play listing, rendered from the real app in
// a widget test (app_deploy_screenshots 1.2). Run with
// `tool/store_screenshots.sh`; images land in build/store_screenshots/, one
// folder per store upload slot, with contact sheets in _review/.
//
// Skipped in the normal suite (dart_test.yaml): it writes ~40 large images.
@Tags(['store_screenshots'])
library;

import 'package:app_deploy_screenshots/app_deploy_screenshots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/app/app.dart';
import 'package:rubric/app/router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/data/sample_data.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/features/home/home_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/db.dart';

/// A Wednesday morning in term: "Good morning", due dates around today.
final _now = DateTime(2026, 10, 7, 9, 30);

/// Fixed ids, so the listing is identical on every run.
const _ns = 'demo';
const _english = 'sample-$_ns-course-english10';
const _bookTalk = 'sample-$_ns-assignment-book-talk';
const _presentation = 'sample-$_ns-rubric-presentation';

/// The brand canvas from lib/design_system: secondary into primaryDark.
const _brand = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [secondary, primaryDark],
);

TextStyle _headline([double? size]) => TextStyle(
  fontFamily: 'Avenir-Black',
  fontWeight: FontWeight.w900,
  color: white,
  fontSize: size,
);
const _sub = TextStyle(fontFamily: 'Avenir-Heavy', color: primaryLighter);
const _accentWords = CaptionEmphasis.color(accent);

/// Apple: a detailed device bleeding off the bottom, as most top listings
/// do. Google Play asks for screenshots without device frames, so Android
/// slides show the screen alone, rounded, under the caption.
MarketingFrame _design(ScreenshotContext shot) =>
    shot.device.platform == DevicePlatform.ios
    ? const MarketingFrame(
        background: FrameBackground.gradient(_brand),
        slideLayout: SlideLayout.bleed(),
        device: DeviceStyle.detailed(),
      )
    : const MarketingFrame(
        background: FrameBackground.gradient(_brand),
        device: DeviceStyle.screenOnly(cornerRadius: 28),
      );

Caption _caption(String headline, [String? sub]) => Caption(
  headline: headline,
  subheadline: sub,
  emphasis: _accentWords,
  headlineStyle: _headline(),
  subheadlineStyle: _sub,
);

/// Ten frames at 100 ms: long enough for the drift streams and the page
/// transitions to land, without waiting on anything that never settles.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('store listing', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.v1': '{"onboardingComplete":true}',
    });
    final prefs = await SharedPreferences.getInstance();
    final db = testDatabase();
    addTearDown(db.close);
    await tester.runAsync(() => loadSampleData(db, now: _now, namespace: _ns));

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        homeClockProvider.overrideWithValue(() => _now),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const RubricApp()),
    );
    await _frames(tester);

    Future<void> go(String location) async {
      container.read(routerProvider).go(location);
      await _frames(tester);
    }

    // The class's best paper, scored by the app's own Scoring.
    final assignments = container.read(assignmentRepositoryProvider);
    final best = await tester.runAsync(() async {
      final graded = [
        for (final e in await assignments.allEvaluations())
          if (e.status == EvaluationStatus.complete)
            (e, (await assignments.get(e.assignmentId))!),
      ];
      double pct((Evaluation, Assignment) p) =>
          Scoring.score(p.$2.rubric, p.$1).percent ?? 0;
      graded.sort((a, b) => pct(b).compareTo(pct(a)));
      return graded.first;
    });
    final (paper, paperAssignment) = best!;

    final listing = StoreListing(
      tester,
      output: const OutputLayout.folders('build/store_screenshots'),
      variants: const [ScreenshotVariant.dark],
      frame: const ScreenshotFrame.builder(_design),
      statusBar: const StatusBarOverlay(),
      customPump: _frames,
    );

    // Capture three screens up front (nothing is written), so the opening
    // slide can show the app before the screenshots that follow.
    await go(Routes.home);
    final home = await listing.captureScreens();
    await go(Routes.rubric(_presentation));
    final rubric = await listing.captureScreens();
    await go(
      Routes.grade(
        paperAssignment.courseId,
        paperAssignment.id,
        paper.studentId,
      ),
    );
    final grading = await listing.captureScreens();

    // 01. The promise, with the app fanned out beneath it.
    await listing.widget(
      'welcome',
      builder: (context, shot) => DecoratedBox(
        decoration: const BoxDecoration(gradient: _brand),
        child: LayoutBuilder(
          builder: (context, box) {
            // Larger phones, running off the bottom edge like the bleed
            // slides that follow.
            final w = box.maxWidth * 0.58;
            final top = box.maxHeight * 0.33;
            Widget phone(ScreenCaptures s, double angle) => Transform.rotate(
              angle: angle,
              child: DeviceMockup(
                screen: s.of(shot),
                style: const DeviceStyle.detailed(),
              ),
            );
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: box.maxHeight * 0.07,
                  left: 24,
                  right: 24,
                  child: Column(
                    children: [
                      Text.rich(
                        TextSpan(
                          style: _headline(44).copyWith(height: 1.1),
                          children: const [
                            TextSpan(text: 'Grading made simple.\n'),
                            TextSpan(
                              text: 'Rubric your way.',
                              style: TextStyle(color: accent),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Weighted rubrics, fast grading and real insight',
                        textAlign: TextAlign.center,
                        style: _sub.copyWith(fontSize: 17),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: top + 70,
                  left: box.maxWidth * 0.5 - w * 1.08,
                  width: w,
                  child: phone(rubric, -0.12),
                ),
                Positioned(
                  top: top + 70,
                  left: box.maxWidth * 0.5 + w * 0.08,
                  width: w,
                  child: phone(grading, 0.12),
                ),
                Positioned(
                  top: top,
                  left: (box.maxWidth - w) / 2,
                  width: w,
                  child: phone(home, 0),
                ),
              ],
            );
          },
        ),
      ),
    );

    // 02. Home: what's waiting, at a glance.
    await go(Routes.home);
    await listing.screenshot(
      'home',
      caption: _caption(
        'Everything to grade, **at a glance**',
        'Classes, students and what is due, the moment you open it',
      ),
    );

    // 03. A rubric: groups, weights, objectives.
    await go(Routes.rubric(_presentation));
    await listing.screenshot(
      'rubric',
      caption: _caption(
        'Weighted rubrics, **built once**',
        'Objectives, groups and weights that always add up',
      ),
    );

    // 04. Grading the best paper, on a tilted device.
    await go(
      Routes.grade(
        paperAssignment.courseId,
        paperAssignment.id,
        paper.studentId,
      ),
    );
    await listing.screenshot(
      'grading',
      caption: _caption(
        'Grade a whole class **in minutes**',
        'Tap a level, and the grade updates live',
      ),
      frame: ScreenshotFrame.builder(
        (shot) => shot.device.platform == DevicePlatform.ios
            ? _design(shot)
                  .copyWith(slideLayout: const SlideLayout.bleed(angle: -6))
            : _design(shot),
      ),
    );

    // 05. Results for one assignment.
    await go(Routes.assignment(_english, _bookTalk));
    await listing.screenshot(
      'results',
      caption: _caption(
        'Class results **as you go**',
        'Mean, median, and who still needs grading',
      ),
    );

    // 06. The gradebook.
    await go(Routes.gradebook(_english));
    await listing.screenshot(
      'gradebook',
      caption: _caption(
        "See **what's landing**",
        'Every student, every assignment, one grid',
      ),
    );

    // 07. Two screens side by side: home and grading.
    await listing.widget(
      'together',
      builder: (context, shot) => DecoratedBox(
        decoration: const BoxDecoration(gradient: _brand),
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth * 0.56;
            return Stack(
              children: [
                Positioned(
                  top: 64,
                  left: 28,
                  right: 28,
                  child: Text.rich(
                    TextSpan(
                      style: _headline(32),
                      children: const [
                        TextSpan(text: 'From the queue\nto the grade, '),
                        TextSpan(
                          text: 'one tap',
                          style: TextStyle(color: accent),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Positioned(
                  top: 210,
                  left: 14,
                  width: width,
                  child: DeviceMockup(
                    screen: home.of(shot),
                    style: const DeviceStyle.detailed(),
                  ),
                ),
                Positioned(
                  top: 310,
                  right: 14,
                  width: width,
                  child: DeviceMockup(
                    screen: grading.of(shot),
                    style: const DeviceStyle.detailed(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    // 08. Templates to start from.
    await go(Routes.templates);
    await listing.screenshot(
      'templates',
      caption: _caption(
        'Start from **a proven template**',
        'Essays, labs, presentations and more, ready to adapt',
      ),
    );

    // 09. Privacy, as the closing promise.
    await listing.poster(
      'private',
      frame: ScreenshotFrame.builder(
        (shot) => MarketingFrame(
          background: const FrameBackground.gradient(_brand),
          caption: Caption(
            headline: 'Works offline.\n**Your classroom stays yours.**',
            subheadline:
                'Everything lives on your device. Sync is optional and '
                'private. No ads, no tracking.',
            emphasis: _accentWords,
            headlineStyle: _headline(42),
            subheadlineStyle: _sub,
          ),
          decorations: [
            // The website's privacy badge: an accent lock on a soft tile.
            FrameDecoration.widget(
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(44),
                ),
                child: const Center(
                  child: Icon(Icons.lock_rounded, color: accent, size: 96),
                ),
              ),
              size: const Size(180, 180),
              // Below the caption, in the open lower half.
              alignment: const Alignment(0, 0.18),
            ),
          ],
        ),
      ),
    );

    final crowded = await listing.writeReport();
    expect(crowded, isEmpty, reason: 'captions over 20% of a Play image');

    // Unmount so drift's stream-teardown timers fire inside the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
