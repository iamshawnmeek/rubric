import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rubric/main.dart' as app;

/// Walks the whole app on a real device from a fresh install, screenshotting
/// every major screen. Run with `tool/tour.sh <device-id>`.
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

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text);
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.tap(f.first);
    await settle(tester);
  }

  testWidgets('tour', (tester) async {
    await binding.convertFlutterSurfaceToImage();
    unawaited(app.main());
    await settle(tester, 3500);
    await shot(tester, 'welcome');

    // Page through onboarding to the last page.
    for (
      var i = 0;
      i < 4 && find.text('Explore with sample data').evaluate().isEmpty;
      i++
    ) {
      if (find.text('Next').evaluate().isEmpty) break;
      await tester.tap(find.text('Next').last);
      await settle(tester);
      await shot(tester, 'welcome_page_${i + 2}');
    }
    await tapText(tester, 'Explore with sample data');
    await settle(tester, 2500);
    await shot(tester, 'home');

    await tester.tap(find.text('Classes').last);
    await shot(tester, 'classes');
    await tester.tap(
      find.byType(Card).evaluate().isNotEmpty
          ? find.byType(Card).first
          : find.textContaining('English').first,
    );
    await shot(tester, 'course');

    // Open the first assignment in the course.
    final assignment = find.textContaining('graded');
    if (assignment.evaluate().isNotEmpty) {
      await tester.tap(assignment.first);
      await shot(tester, 'assignment');
      final start = find.textContaining('grading');
      if (start.evaluate().isNotEmpty) {
        await tester.tap(start.last);
        await shot(tester, 'grading');
        await tester.pageBack();
        await settle(tester);
      }
      await tester.pageBack();
      await settle(tester);
    }
    final gradebook = find.byTooltip('Gradebook');
    if (gradebook.evaluate().isNotEmpty) {
      await tester.tap(gradebook.first);
      await shot(tester, 'gradebook');
      await tester.pageBack();
      await settle(tester);
    }

    await tester.tap(find.text('Rubrics').last);
    await shot(tester, 'rubrics');
    await tester.tap(find.text('Settings').last);
    await shot(tester, 'settings');
    await tester.tap(find.text('Home').last);
    await shot(tester, 'home_again');
  });
}
