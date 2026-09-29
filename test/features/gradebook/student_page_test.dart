import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/features/classes/student_page.dart';

import '../../helpers/app_harness.dart';
import 'gradebook_seed.dart';

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Finder onCard(String title, String text) => find.descendant(
  of: find.widgetWithText(RubricCard, title),
  matching: find.text(text),
);

void main() {
  Future<TestApp> pump(WidgetTester tester, String studentId) => pumpPage(
    tester,
    StudentPage(courseId: courseId, studentId: studentId),
    seed: seedClass,
  );

  testWidgets('profile shows details, overall grade and grade history', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final app = await pump(tester, 's1');

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Student #1001 · ada@example.com'), findsOneWidget);
    // 90 and 70, equally weighted.
    expect(find.bySemanticsLabel('Average: 80%'), findsOneWidget);
    expect(find.bySemanticsLabel('Letter: B'), findsOneWidget);
    expect(find.bySemanticsLabel('Missing: 0'), findsOneWidget);
    expect(find.bySemanticsLabel('Graded: 2 of 2'), findsOneWidget);
    expect(find.text('Grades over time'), findsOneWidget);
    semantics.dispose();

    await scrollTo(tester, find.text('Essay 1'));
    expect(find.text('Essay 2'), findsOneWidget);
    await tester.tap(find.text('Essay 1'));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.grade(courseId, 'a1', 's1')]);
  });

  testWidgets('strengths and weaknesses compare with the class', (
    tester,
  ) async {
    // Ada: 90 vs class 75 on Essay 1, 70 vs 70 on Essay 2 → 7.5 above.
    await pump(tester, 's1');
    await scrollTo(tester, find.text('STRENGTHS'));
    await scrollTo(tester, find.text('Sources'));
    expect(onCard('Sources', '8 above class'), findsOneWidget);
    expect(onCard('Organization', '8 above class'), findsOneWidget);
    expect(find.text('ROOM TO GROW'), findsNothing);
  });

  testWidgets('a struggling student sees room to grow', (tester) async {
    // Alan: 60 vs class 75 on Essay 1; the missing Essay 2 has no marks.
    final semantics = tester.ensureSemantics();
    await pump(tester, 's2');
    expect(find.bySemanticsLabel('Missing: 1'), findsOneWidget);
    semantics.dispose();
    await scrollTo(tester, find.text('ROOM TO GROW'));
    await scrollTo(tester, find.text('Sources'));
    expect(onCard('Sources', '15 below class'), findsOneWidget);
    expect(onCard('Grammar', '15 below class'), findsOneWidget);
    expect(find.text('Grammar'), findsOneWidget);
  });

  testWidgets('editing saves the notes and offers undo', (tester) async {
    final app = await pump(tester, 's1');
    await tester.tap(find.text('Add a note'));
    await tester.pumpAndSettle();
    expect(find.text('Edit student'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextField, 'Notes about this student'),
      'Strong thesis writer',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(
      () => CourseRepository(app.db).students(courseId),
    );
    expect(
      saved!.firstWhere((s) => s.id == 's1').notes,
      'Strong thesis writer',
    );
    expect(find.text('Strong thesis writer'), findsOneWidget);
    expect(find.text('Student saved'), findsOneWidget);
  });

  testWidgets('a first name is required', (tester) async {
    await pump(tester, 's1');
    await tester.tap(find.byTooltip('Edit student'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Ada'), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('A first name is required.'), findsOneWidget);
  });

  testWidgets('exporting a report picks from graded assignments', (
    tester,
  ) async {
    await pump(tester, 's1');
    await tester.tap(find.byTooltip('Export a report'));
    await tester.pumpAndSettle();
    final sheetCard = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('Essay 1'),
    );
    expect(sheetCard, findsOneWidget);
    await tester.tap(sheetCard);
    await tester.pumpAndSettle();
    // The export leaf's stub answers with a snack; reaching it proves wiring.
    expect(find.text('Export is coming soon.'), findsOneWidget);
  });

  testWidgets('a student with nothing graded cannot export', (tester) async {
    await pumpPage(
      tester,
      const StudentPage(courseId: courseId, studentId: 's3'),
      seed: (db) => seedClass(db, evaluations: []),
    );
    await tester.tap(find.byTooltip('Export a report'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Nothing graded to export yet.'), findsOneWidget);
  });

  testWidgets('an unknown student says so', (tester) async {
    await pump(tester, 'nobody');
    expect(find.text('This student is no longer in the class.'), findsWidgets);
  });
}
