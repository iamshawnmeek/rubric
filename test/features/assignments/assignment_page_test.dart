import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/features/assignments/assignment_page.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fixtures.dart';

const _students = [
  Student(id: 's1', courseId: 'c1', firstName: 'Ada', lastName: 'Lovelace'),
  Student(id: 's2', courseId: 'c1', firstName: 'Alan', lastName: 'Turing'),
  Student(id: 's3', courseId: 'c1', firstName: 'Grace', lastName: 'Hopper'),
];

Evaluation _eval(
  String student,
  EvaluationStatus status, [
  Map<String, ObjectiveScore> scores = const {},
]) => Evaluation(
  id: 'e-$student',
  assignmentId: 'a1',
  studentId: student,
  status: status,
  scores: scores,
  updatedAt: t0,
);

Future<void> _seed(AppDatabase db, {List<Student> students = _students}) async {
  final courses = CourseRepository(db);
  await courses.saveCourse(Course(id: 'c1', name: 'English 10', createdAt: t0));
  await courses.saveStudents(students);
  await RubricRepository(db).save(essayRubric());
  final repo = AssignmentRepository(db);
  await repo.save(
    Assignment(
      id: 'a1',
      courseId: 'c1',
      title: 'Persuasive essay',
      rubric: essayRubric(),
      sourceRubricId: 'r1',
      createdAt: t0,
    ),
  );
  await repo.saveEvaluations([
    _eval('s1', EvaluationStatus.complete, const {
      'o1': PercentScore(100),
      'o2': PercentScore(80),
      'o3': PercentScore(90),
    }),
    _eval('s2', EvaluationStatus.inProgress, const {'o1': PercentScore(50)}),
    _eval('s3', EvaluationStatus.missing),
  ]);
}

Future<TestApp> _pump(
  WidgetTester tester, {
  Future<void> Function(AppDatabase db)? seed,
}) => pumpPage(
  tester,
  const AssignmentPage(courseId: 'c1', assignmentId: 'a1'),
  seed: seed ?? _seed,
  size: const Size(390, 1600),
);

String _gradeOf(WidgetTester tester, String studentId) =>
    tester.widget<Text>(find.byKey(Key('assignments.grade.$studentId'))).data!;

void main() {
  testWidgets('shows a spinner, not a crash, while the roster is loading', (
    tester,
  ) async {
    // Regression (seen on device): with the assignment loaded but students
    // still loading, the page built a box inside a sliver list.
    final roster = StreamController<List<Student>>();
    addTearDown(roster.close);
    await pumpPage(
      tester,
      const AssignmentPage(courseId: 'c1', assignmentId: 'a1'),
      seed: _seed,
      settle: false,
      size: const Size(390, 1600),
      overrides: [studentsProvider('c1').overrideWith((ref) => roster.stream)],
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    roster.add(_students);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assignments.grade.s1')), findsOneWidget);
  });

  testWidgets('shows each student status and grade from the evaluations', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Persuasive essay'), findsOneWidget);
    expect(find.text('2 of 3 graded'), findsOneWidget);
    expect(_gradeOf(tester, 's1'), '90% · A');
    expect(_gradeOf(tester, 's2'), '50% · F');
    expect(_gradeOf(tester, 's3'), '0% · F');
    expect(find.text('Complete'), findsWidgets);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    // Weakest objective: Grammar averages (100+50)/2; the missing paper has
    // no objective scores, so it only counts toward the overall grade.
    expect(find.text('Grammar · 75%'), findsOneWidget);
  });

  testWidgets('Continue grading jumps to the first ungraded student', (
    tester,
  ) async {
    final app = await _pump(tester);
    await tester.tap(find.byKey(const Key('assignments.gradeCta')));
    await tester.pumpAndSettle();
    expect(app.visited, [Routes.grade('c1', 'a1', 's2')]);
  });

  testWidgets('a student added after creation gets an evaluation on open', (
    tester,
  ) async {
    final app = await _pump(
      tester,
      seed: (db) => _seed(
        db,
        students: [
          ..._students,
          const Student(
            id: 's4',
            courseId: 'c1',
            firstName: 'Edsger',
            lastName: 'Dijkstra',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final created = await tester.runAsync(
      () => AssignmentRepository(app.db).getEvaluation('a1', 's4'),
    );
    expect(created, isNotNull);
    expect(created!.status, EvaluationStatus.notStarted);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('2 of 4 graded'), findsOneWidget);
  });

  testWidgets('marking a student excused updates the row and can be undone', (
    tester,
  ) async {
    final app = await _pump(tester);
    await tester.tap(find.byKey(const Key('assignments.actions.s2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excuse'));
    await tester.pumpAndSettle();

    final repo = AssignmentRepository(app.db);
    var e = await tester.runAsync(() => repo.getEvaluation('a1', 's2'));
    expect(e!.status, EvaluationStatus.excused);
    expect(_gradeOf(tester, 's2'), '—');

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    e = await tester.runAsync(() => repo.getEvaluation('a1', 's2'));
    expect(e!.status, EvaluationStatus.inProgress);
  });

  testWidgets('updating the rubric from the library keeps surviving scores', (
    tester,
  ) async {
    final app = await _pump(tester);
    // The library rubric loses "Organization" (o2).
    final library = essayRubric();
    await tester.runAsync(
      () => RubricRepository(app.db).save(
        library.copyWith(
          title: 'Essay v2',
          groups: [
            library.groups[0].copyWith(
              objectives: [library.groups[0].objectives[0]],
            ),
            library.groups[1],
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('assignments.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignments.menu.updateRubric')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Scores on objectives that still exist'),
      findsOneWidget,
    );
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    final repo = AssignmentRepository(app.db);
    final assignment = (await tester.runAsync(() => repo.get('a1')))!;
    expect(assignment.rubric.title, 'Essay v2');
    final e = (await tester.runAsync(() => repo.getEvaluation('a1', 's1')))!;
    expect(e.scores, {
      'o1': const PercentScore(100),
      'o3': const PercentScore(90),
    });
    expect(e.status, EvaluationStatus.complete);
  });

  testWidgets('deleting asks first, then leaves for the course', (
    tester,
  ) async {
    final app = await _pump(tester);
    await tester.tap(find.byKey(const Key('assignments.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assignments.menu.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(app.visited, [Routes.course('c1')]);
    expect(
      await tester.runAsync(() => AssignmentRepository(app.db).get('a1')),
      isNull,
    );
  });
}
