import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rubric/app/app.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/data/sample_data.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

/// Screens for the public website that the tour can't reach: a student whose
/// work is fully graded. Run by `tool/site_screens.sh <device>`; output lands
/// in build/screens/.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('site screens', (tester) async {
    await binding.convertFlutterSurfaceToImage();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'settings.v1',
      jsonEncode(const AppSettings(onboardingComplete: true).toJson()),
    );
    unawaited(app.main());
    await settle(tester, 3500);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RubricApp)),
    );
    await loadSampleData(container.read(databaseProvider));
    await settle(tester, 1500);

    // A complete, high-scoring evaluation makes the grading screen show
    // what it is for: levels picked and a live grade.
    final assignments = container.read(assignmentRepositoryProvider);
    final graded = [
      for (final e in await assignments.allEvaluations())
        if (e.status == EvaluationStatus.complete) e,
    ];
    expect(graded, isNotEmpty, reason: 'the sample class has graded work');
    // The class's best paper: the screen should show a grade to be proud of.
    double percentOf((Evaluation, Assignment) p) =>
        Scoring.score(p.$2.rubric, p.$1).percent ?? 0;
    final scored = [
      for (final e in graded) (e, (await assignments.get(e.assignmentId))!),
    ]..sort((a, b) => percentOf(b).compareTo(percentOf(a)));
    final (pick, assignment) = scored.first;

    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go(Routes.grade(assignment.courseId, assignment.id, pick.studentId));
    await settle(tester, 2500);
    await binding.takeScreenshot('site_grading');
  });
}
