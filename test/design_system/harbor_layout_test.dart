import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harbor/harbor.dart';
import 'package:harbor_test/harbor_test.dart';
import 'package:rubric/app/app.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/db.dart';

/// Where things land on real phone geometry (harbor's sea-trial devices:
/// status bar, home indicator, keyboard), measured rather than assumed.
/// Each of these failed before Rubric moved onto harbor; see the PR.

Widget _app(Widget home) => MaterialApp(
  theme: buildRubricTheme(),
  builder: (context, child) => HarborSea(child: child!),
  home: home,
);

const _ctaKey = Key('cta');
const _lastKey = Key('last row');

/// A page whose CTA is as tall as [ctaHeight]: the builder's ungrouped tray
/// grows with its cards, so a docked CTA's height is not a constant.
Widget _page({double ctaHeight = Sizes.ctaHeight, Widget? last}) => RubricPage(
  title: 'Page',
  showBack: false,
  bottomCta: SizedBox(
    key: _ctaKey,
    width: 200,
    height: ctaHeight,
    child: const ColoredBox(color: accent),
  ),
  children: [
    for (var i = 0; i < 30; i++) SizedBox(height: 60, child: Text('row $i')),
    last ?? const SizedBox(key: _lastKey, height: 60),
  ],
);

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -10000));
  await tester.pumpAndSettle();
}

void main() {
  for (final device in HarborTrialDevice.phones) {
    group(device.name, () {
      testWidgets('the last row rests clear of the docked CTA', (tester) async {
        await tester.pumpSeaTrial(_app(_page()), device: device);
        await _scrollToEnd(tester);

        final last = tester.getRect(find.byKey(_lastKey));
        final cta = tester.getRect(find.byKey(_ctaKey));
        expect(last.bottom, lessThanOrEqualTo(cta.top));
        // And the CTA itself clears the home indicator.
        expect(
          cta.bottom,
          lessThanOrEqualTo(device.size.height - device.coast.bottom),
        );
      });

      testWidgets('...however tall the CTA lays out', (tester) async {
        // The old page reserved a fixed 130pt; a 300pt CTA covered rows.
        await tester.pumpSeaTrial(_app(_page(ctaHeight: 300)), device: device);
        await _scrollToEnd(tester);

        expect(
          tester.getRect(find.byKey(_lastKey)).bottom,
          lessThanOrEqualTo(tester.getRect(find.byKey(_ctaKey)).top),
        );
      });
    });
  }

  testWidgets('a focused field at the end stays clear of the CTA and the '
      'keyboard', (tester) async {
    const field = Key('field');
    final trial = await tester.pumpSeaTrial(
      _app(_page(last: const TextField(key: field))),
    );
    await _scrollToEnd(tester);
    await tester.tap(find.byKey(field));
    await trial.raiseTide(settle: true);

    final cta = tester.getRect(find.byKey(_ctaKey));
    // The CTA rides the keyboard, as the docked FAB did...
    expect(cta.bottom, lessThanOrEqualTo(trial.waterline));
    // ...and the field being typed in is not underneath it.
    expect(
      tester.getRect(find.byKey(field)).bottom,
      lessThanOrEqualTo(cta.top),
    );
  });

  group('showRubricSheet', () {
    const sheet = Key('sheet');

    Future<HarborSeaTrial> open(WidgetTester tester) async {
      final trial = await tester.pumpSeaTrial(
        _app(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showRubricSheet<void>(
                  context: context,
                  child: const RubricSheet(
                    key: sheet,
                    child: TextField(autofocus: true),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return trial;
    }

    testWidgets('floats 12pt above the home indicator', (tester) async {
      final trial = await open(tester);
      // It used to add the keyboard and nothing else: 12pt above the
      // screen's edge, inside the home indicator.
      expect(
        tester.getRect(find.byKey(sheet)).bottom,
        moreOrLessEquals(
          trial.device.size.height - trial.device.coast.bottom - Insets.sm,
        ),
      );
    });

    testWidgets('and 12pt above the keyboard', (tester) async {
      final trial = await open(tester);
      await trial.raiseTide(settle: true);
      expect(
        tester.getRect(find.byKey(sheet)).bottom,
        moreOrLessEquals(trial.waterline - Insets.sm),
      );
    });
  });

  testWidgets('on a tablet the rail keeps its width and the page gets the '
      'rest', (tester) async {
    // Found in a rendered iPad screenshot, not by any test: as a harbor side
    // dock, NavigationRail took the whole width and the page vanished.
    SharedPreferences.setMockInitialValues({
      'settings.v1': '{"onboardingComplete":true}',
    });
    final prefs = await SharedPreferences.getInstance();
    final db = testDatabase();
    addTearDown(db.close);
    await tester.pumpSeaTrial(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
        ],
        child: const RubricApp(),
      ),
      device: HarborTrialDevice.foldableOpen,
    );
    await tester.pumpAndSettle();

    // Logical sizes: harbor_test runs devices at their real pixel ratio, so
    // the view's physical size is no longer the screen's logical width.
    final screen = HarborTrialDevice.foldableOpen.size.width;
    final rail = tester.getRect(find.byType(NavigationRail));
    // Its own width (128 with labels here), not the screen's (750).
    expect(rail.width, lessThan(screen / 5));
    final page = tester.getRect(find.byType(RubricPage));
    expect(page.left, moreOrLessEquals(rail.right));
    expect(page.width, greaterThan(screen / 2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the nav bar pads for the home indicator once', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.v1': '{"onboardingComplete":true}',
    });
    final prefs = await SharedPreferences.getInstance();
    final db = testDatabase();
    addTearDown(db.close);
    final trial = await tester.pumpSeaTrial(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
        ],
        child: const RubricApp(),
      ),
    );
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(NavigationBar));
    final height = buildRubricTheme().navigationBarTheme.height!;
    // The bar sits on the home indicator at its own height: harbor's dock
    // absorbs the coast, so the bar must not pad for it a second time.
    expect(bar.bottom, trial.device.size.height - trial.device.coast.bottom);
    expect(bar.height, height);
    // And the dock's ground, where its backdrop is painted, runs to the
    // screen's edge, so no strip of page shows under the bar.
    final dock = trial
        .docksAround(find.byType(NavigationBar))
        .singleWhere((d) => d.edge == HarborEdge.bottom);
    expect(dock.rect.bottom, trial.device.size.height);
    expect(dock.rect.height, height + trial.device.coast.bottom);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
