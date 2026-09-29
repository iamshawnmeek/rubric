import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/features/classes/course_page.dart';

import '../../helpers/app_harness.dart';
import 'classes_seed.dart';

Future<void> _openStudents(WidgetTester tester) async {
  await tester.tap(find.text('Students'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the class header and routes to the gradebook', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const CoursePage(courseId: courseId),
      seed: seedBiology,
    );
    expect(find.text('Biology'), findsOneWidget);
    expect(find.text('Period 3 · Fall 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Gradebook'));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.gradebook(courseId)]);
  });

  testWidgets('assignments show due date and graded x/y, and open', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const CoursePage(courseId: courseId),
      seed: (db) => seedBiology(db, graded: true),
    );
    expect(find.text('Cell Essay'), findsOneWidget);
    expect(find.text('Due Oct 3'), findsOneWidget);
    // Ada is complete, Grace not started.
    expect(find.text('1 of 2 graded'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Due Oct 3, Cell Essay')),
      isSemantics(value: '1 of 2 graded', hasTapAction: true),
    );
    semantics.dispose();

    await tester.tap(find.text('Cell Essay'));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.assignment(courseId, 'a1')]);
  });

  testWidgets('New Assignment routes to the assignment builder', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const CoursePage(courseId: courseId),
      seed: seedBiology,
    );
    expect(find.text('No assignments yet'), findsOneWidget);
    await tester.tap(find.text('New Assignment'));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.newAssignment(courseId)]);
  });

  testWidgets('adding a student saves them to the roster', (tester) async {
    final app = await pumpPage(
      tester,
      const CoursePage(courseId: courseId),
      seed: seedBiology,
    );
    await _openStudents(tester);
    expect(find.text('Hopper, Grace'), findsOneWidget);
    expect(find.text('Lovelace, Ada'), findsOneWidget);

    await tester.tap(find.text('Add Student'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Required'), 'Alan');
    await tester.enterText(field('Optional').at(0), 'Turing');
    await tester.enterText(field('Optional').at(1), '1003');
    await tester.enterText(field('Optional').at(2), 'alan@school.org');
    await tester.pump();
    // The sheet's CTA shares the page CTA's label; the sheet's is the last.
    await tester.tap(find.text('Add Student').last);
    await tester.pumpAndSettle();

    final alan = (await studentsIn(
      tester,
      app.db,
    )).firstWhere((s) => s.firstName == 'Alan');
    expect(alan.lastName, 'Turing');
    expect(alan.studentNumber, '1003');
    expect(alan.email, 'alan@school.org');
    expect(find.text('Turing, Alan'), findsOneWidget);
    expect(find.text('#1003 · alan@school.org'), findsOneWidget);
  });

  testWidgets('the add sheet warns about a duplicate student number', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const CoursePage(courseId: courseId),
      seed: seedBiology,
    );
    await _openStudents(tester);
    await tester.tap(find.text('Add Student'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Required'), 'Augusta');
    await tester.enterText(field('Optional').at(1), '1001');
    await tester.pump();
    expect(
      find.text('Someone with this name or number is already in this class.'),
      findsOneWidget,
    );
  });

  testWidgets('pasting names adds new students and skips existing ones', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const CoursePage(courseId: courseId),
      seed: seedBiology,
    );
    await _openStudents(tester);
    await tester.tap(find.text('Paste Names'));
    await tester.pumpAndSettle();

    await tester.enterText(
      field('One name per line\nLovelace, Ada\nGrace Hopper'),
      'Turing, Alan\nKatherine Johnson\n\nHopper, Grace\n',
    );
    await tester.pump();
    expect(find.text('2 students will be added'), findsOneWidget);
    expect(
      find.text('1 name is already in the class and will be skipped'),
      findsOneWidget,
    );

    await tester.tap(find.text('Add 2 Students'));
    await tester.pumpAndSettle();

    final names = (await studentsIn(tester, app.db)).map((s) => s.sortName);
    expect(names, [
      'Hopper, Grace',
      'Johnson, Katherine',
      'Lovelace, Ada',
      'Turing, Alan',
    ]);
    expect(find.text('2 students added'), findsOneWidget);
  });

  testWidgets('search filters the roster by name or number', (tester) async {
    await pumpPage(
      tester,
      const CoursePage(courseId: courseId),
      seed: seedBiology,
    );
    await _openStudents(tester);

    await tester.enterText(field('Search students'), 'hop');
    await tester.pumpAndSettle();
    expect(find.text('Hopper, Grace'), findsOneWidget);
    expect(find.text('Lovelace, Ada'), findsNothing);

    await tester.enterText(field('hop'), '1001');
    await tester.pumpAndSettle();
    expect(find.text('Lovelace, Ada'), findsOneWidget);
    expect(find.text('Hopper, Grace'), findsNothing);

    await tester.enterText(field('1001'), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No students match “zzz”'), findsOneWidget);
  });

  testWidgets('archiving a student hides them until archived are shown', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const CoursePage(courseId: courseId),
      seed: seedBiology,
    );
    await _openStudents(tester);

    await tester.tap(find.byTooltip('Actions for Grace Hopper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Hopper, Grace'), findsNothing);
    final grace = (await studentsIn(
      tester,
      app.db,
    )).firstWhere((s) => s.id == 's2');
    expect(grace.archived, isTrue);

    await tester.tap(find.text('Show 1 archived student'));
    await tester.pumpAndSettle();
    expect(find.text('Hopper, Grace'), findsOneWidget);
    expect(find.textContaining('Archived · #1002'), findsOneWidget);
  });

  testWidgets('removing a student asks first, then deletes them', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const CoursePage(courseId: courseId),
      seed: seedBiology,
    );
    await _openStudents(tester);

    await tester.tap(find.byTooltip('Actions for Ada Lovelace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from Class'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Ada Lovelace?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect((await studentsIn(tester, app.db)).map((s) => s.id), ['s2']);
    expect(find.text('Lovelace, Ada'), findsNothing);
  });

  testWidgets('a missing class offers a way back', (tester) async {
    final app = await pumpPage(tester, const CoursePage(courseId: 'gone'));
    expect(find.text('This class no longer exists.'), findsOneWidget);
    await tester.tap(find.text('Back to Classes'));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.classes]);
  });

  testWidgets('deleting from the class page returns to Classes', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const CoursePage(courseId: courseId),
      seed: seedBiology,
    );
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Class'));
    await tester.pumpAndSettle();

    expect(
      await tester.runAsync(() => CourseRepository(app.db).getCourse(courseId)),
      isNull,
    );
    expect(app.visited, [Routes.classes]);
  });
}
