import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/app/routes.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/features/gradebook/gradebook_page.dart';

import '../../helpers/app_harness.dart';
import 'gradebook_seed.dart';

void main() {
  Future<TestApp> pump(
    WidgetTester tester, {
    bool withAssignments = true,
    List<Evaluation>? evaluations,
    Size size = const Size(390, 844),
  }) => pumpPage(
    tester,
    const GradebookPage(courseId: courseId),
    size: size,
    seed: (db) => seedClass(
      db,
      withAssignments: withAssignments,
      evaluations: evaluations,
    ),
  );

  testWidgets('grid shows every student, grade, status and average', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    expect(find.text('Gradebook'), findsOneWidget);
    expect(find.text('Period 3 English'), findsOneWidget);
    for (final name in ['Hopper, Grace', 'Lovelace, Ada', 'Turing, Alan']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Essay 1'), findsOneWidget);
    expect(find.text('Essay 2'), findsOneWidget);
    expect(find.text('Due Sep 5'), findsOneWidget);

    // Cells carry grade text and a spoken status, never color alone.
    expect(
      find.bySemanticsLabel(RegExp(r'^Ada Lovelace, Essay 1: 90%, A\. Graded')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Alan Turing, Essay 2: 0%, F\. Missing')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Grace Hopper, Essay 1: —\. Excused')),
      findsOneWidget,
    );
    expect(find.text('EX'), findsOneWidget);

    // Averages: Ada 80 (90, 70); Alan 30 (60, missing 0); Grace none.
    expect(
      find.bySemanticsLabel(RegExp(r'^Ada Lovelace, average 80%, B\.')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Alan Turing, average 30%, F\.')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Grace Hopper, average —\.')),
      findsOneWidget,
    );

    // Column footers: Essay 1 mean of 90 and 60; Essay 2 of 70 and 0.
    expect(
      find.bySemanticsLabel('Class mean, Essay 1: 75%, C'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Class mean, Essay 2: 35%, F'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('tapping a cell opens grading for that student and assignment', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final app = await pump(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('^Alan Turing, Essay 1:')));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.grade(courseId, 'a1', 's2')]);
    semantics.dispose();
  });

  testWidgets('tapping a name opens the student, a header the assignment', (
    tester,
  ) async {
    final app = await pump(tester);
    await tester.tap(find.text('Lovelace, Ada'));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.student(courseId, 's1')]);

    app.router.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Essay 1'));
    await tester.pumpAndSettle();
    expect(app.visited.last, Routes.assignment(courseId, 'a1'));
  });

  testWidgets('letters toggle shows each cell as its letter', (tester) async {
    await pump(tester);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('A'), findsNothing);

    await tester.tap(find.text('Letters'));
    await tester.pumpAndSettle();
    expect(find.text('90%'), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('sort by average puts the highest first, then reverses', (
    tester,
  ) async {
    await pump(tester);
    double y(String name) => tester.getTopLeft(find.text(name)).dy;

    expect(y('Hopper, Grace'), lessThan(y('Lovelace, Ada')));

    await tester.tap(find.text('Average'));
    await tester.pumpAndSettle();
    expect(y('Lovelace, Ada'), lessThan(y('Turing, Alan')));
    expect(y('Turing, Alan'), lessThan(y('Hopper, Grace')));

    await tester.tap(find.text('Average'));
    await tester.pumpAndSettle();
    expect(y('Turing, Alan'), lessThan(y('Lovelace, Ada')));
    // No average stays last either way.
    expect(y('Lovelace, Ada'), lessThan(y('Hopper, Grace')));
  });

  testWidgets('export hands the course to the CSV exporter', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Export gradebook as CSV'));
    await tester.pump();
    // The export leaf's stub answers with a snack; reaching it proves wiring.
    expect(find.text('Export is coming soon.'), findsOneWidget);
  });

  testWidgets('a class with no assignments says so', (tester) async {
    await pump(tester, withAssignments: false);
    expect(find.text('No assignments yet'), findsOneWidget);
    expect(find.byTooltip('Export gradebook as CSV'), findsNothing);
  });

  testWidgets('a missing class says so', (tester) async {
    await pumpPage(tester, const GradebookPage(courseId: 'nope'));
    expect(find.text('This class no longer exists.'), findsOneWidget);
  });

  testWidgets('analytics flags students who need attention', (tester) async {
    final app = await pump(
      tester,
      evaluations: [
        // Ada drops from 90 to an average of 70.
        gradedAt('s1', 'a1', 90),
        gradedAt('s1', 'a2', 50),
        gradedAt('s2', 'a1', 80),
        gradedAt('s2', 'a2', 85),
        // Grace: two missing.
        markedAs('s3', 'a1', EvaluationStatus.missing),
        markedAs('s3', 'a2', EvaluationStatus.missing),
      ],
    );
    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();

    expect(find.text('Score distribution'), findsOneWidget);
    expect(find.text('Letter grades'), findsOneWidget);
    expect(find.text('Class average over time'), findsOneWidget);
    expect(find.text('Objective mastery'), findsOneWidget);
    expect(find.text('Grammar'), findsOneWidget);

    await tester.ensureVisible(find.text('Grace Hopper'));
    await tester.pumpAndSettle();
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.text('2 missing'), findsOneWidget);
    expect(find.text('Average down 20 pts'), findsOneWidget);
    expect(find.text('Alan Turing'), findsNothing);

    await tester.tap(find.text('Grace Hopper'));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.student(courseId, 's3')]);
  });

  testWidgets('analytics with nothing graded shows an empty state', (
    tester,
  ) async {
    await pump(tester, evaluations: []);
    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing graded yet'), findsOneWidget);
  });

  testWidgets('lays out on a tablet without overflow', (tester) async {
    await pump(tester, size: const Size(1024, 1366));
    expect(find.text('Lovelace, Ada'), findsOneWidget);
    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
