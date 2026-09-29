import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/main.dart' as app;

/// Walks the whole app on a real device from a fresh install, screenshotting
/// every major screen. Run with `tool/tour.sh <device-id>`.
///
/// Each leg is independent: a leg that cannot find its way records why and
/// the tour carries on, so one broken screen does not hide the rest. Any leg
/// failure — or any framework exception — fails the run at the end.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );
  }

  var shotIndex = 0;
  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    shotIndex++;
    await binding.takeScreenshot(
      '${shotIndex.toString().padLeft(2, '0')}_$name',
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    expect(finder, findsAny, reason: 'nothing to tap: $finder');
    await tester.ensureVisible(finder.first);
    await settle(tester, 200);
    await tester.tap(finder.first);
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) =>
      tap(tester, find.byType(BackChevron));

  Future<void> tab(WidgetTester tester, String label) => tap(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );

  final failures = <String>[];
  Future<void> leg(String name, Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (e) {
      failures.add('$name: $e');
    }
  }

  testWidgets('tour', (tester) async {
    await binding.convertFlutterSurfaceToImage();
    unawaited(app.main());
    await settle(tester, 3500);
    await shot(tester, 'welcome');

    await leg('onboarding', () async {
      for (var i = 0; i < 2; i++) {
        await tap(tester, find.text('Next'));
      }
      await shot(tester, 'welcome_last');
      await tap(tester, find.text('Explore with sample data'));
      await settle(tester, 3000);
      await shot(tester, 'home');
    });

    await leg('classes', () async {
      await tab(tester, 'Classes');
      await shot(tester, 'classes');
      await tap(tester, find.text('English 10'));
      await shot(tester, 'course');
      await tap(tester, find.text('Students'));
      await shot(tester, 'course_students');
      await tap(tester, find.text('Assignments'));
    });

    await leg('assignment + grading', () async {
      await tap(tester, find.textContaining('Book Talk'));
      await shot(tester, 'assignment');
      final cta = find.byKey(const Key('assignments.gradeCta'));
      await tap(tester, cta);
      await shot(tester, 'grading');
      await settle(tester);
      await back(tester);
      await back(tester);
    });

    await leg('gradebook', () async {
      // Start from a known place rather than trusting the previous leg's backs.
      await tab(tester, 'Classes');
      if (find.byTooltip('Gradebook').evaluate().isEmpty) {
        await tap(tester, find.text('English 10'));
      }
      await tap(tester, find.byTooltip('Gradebook'));
      await shot(tester, 'gradebook');
      await back(tester);
      await back(tester);
    });

    await leg('rubrics', () async {
      await tab(tester, 'Rubrics');
      await shot(tester, 'rubrics');
      await tap(tester, find.text('Oral Presentation'));
      await shot(tester, 'rubric_detail');
      await back(tester);
      await tap(tester, find.text('Start from a template'));
      await shot(tester, 'templates');
      await back(tester);
    });

    await leg('builder', () async {
      await tap(tester, find.text('New Rubric'));
      await shot(tester, 'builder_objectives');
    });

    await leg('settings', () async {
      // The builder is full-screen; leave it the way a person would.
      if (find.byType(BackChevron).evaluate().isNotEmpty) {
        await back(tester);
        final discard = find.text('Discard');
        if (discard.evaluate().isNotEmpty) await tap(tester, discard);
      }
      await tab(tester, 'Settings');
      await shot(tester, 'settings');
    });

    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
