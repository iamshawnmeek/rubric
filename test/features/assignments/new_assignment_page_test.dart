import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/features/assignments/new_assignment_page.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fixtures.dart';

Future<void> _seed(AppDatabase db) async {
  final courses = CourseRepository(db);
  await courses.saveCourse(Course(id: 'c1', name: 'English 10', createdAt: t0));
  await courses.saveStudents([
    const Student(id: 's1', courseId: 'c1', firstName: 'Ada', lastName: 'L'),
    const Student(id: 's2', courseId: 'c1', firstName: 'Alan', lastName: 'T'),
    const Student(
      id: 's3',
      courseId: 'c1',
      firstName: 'Old',
      lastName: 'Timer',
      archived: true,
    ),
  ]);
  final rubrics = RubricRepository(db);
  await rubrics.save(essayRubric());
  // Weights add to 60, so it cannot be graded against.
  await rubrics.save(
    essayRubric()
        .duplicate(title: 'Broken')
        .copyWith(groups: [essayRubric().groups.first]),
  );
}

void main() {
  testWidgets('creating an assignment snapshots the rubric and seeds '
      'evaluations for active students', (tester) async {
    final app = await pumpPage(
      tester,
      const NewAssignmentPage(courseId: 'c1'),
      seed: _seed,
      size: const Size(390, 1400),
    );

    await tester.enterText(
      find.byKey(const Key('assignments.title')),
      'Persuasive essay',
    );
    await tester.tap(find.byKey(const Key('assignments.chooseRubric')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Essay'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assignments.chosenRubric')), findsOneWidget);

    await tester.tap(find.byKey(const Key('assignments.create')));
    await tester.pumpAndSettle();

    final repo = AssignmentRepository(app.db);
    final saved = (await tester.runAsync(repo.all))!;
    expect(saved, hasLength(1));
    final assignment = saved.single;
    expect(assignment.title, 'Persuasive essay');
    expect(assignment.pointsPossible, 100);
    expect(assignment.sourceRubricId, 'r1');
    expect(
      assignment.rubric.objectives.map((o) => o.id),
      essayRubric().objectives.map((o) => o.id),
    );

    final evaluations = (await tester.runAsync(
      () => repo.evaluations(assignment.id),
    ))!;
    expect(evaluations.map((e) => e.studentId).toSet(), {'s1', 's2'});
    expect(
      evaluations.every((e) => e.status == EvaluationStatus.notStarted),
      isTrue,
    );
    expect(app.visited, contains(Routes.assignment('c1', assignment.id)));

    // Later library edits do not reach the snapshot.
    await tester.runAsync(
      () => RubricRepository(app.db).save(essayRubric().copyWith(title: 'X')),
    );
    final reread = (await tester.runAsync(() => repo.get(assignment.id)))!;
    expect(reread.rubric.title, 'Essay');
  });

  testWidgets('a rubric with issues cannot be picked and offers Fix', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const NewAssignmentPage(courseId: 'c1'),
      seed: _seed,
      size: const Size(390, 1400),
    );
    await tester.enterText(find.byKey(const Key('assignments.title')), 'Lab');
    await tester.tap(find.byKey(const Key('assignments.chooseRubric')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not ready'), findsOneWidget);
    await tester.tap(find.text('Broken'));
    await tester.pumpAndSettle();
    // Still in the sheet, nothing chosen.
    expect(find.text('Choose a rubric'), findsWidgets);
    expect(find.byKey(const Key('assignments.chosenRubric')), findsNothing);

    await tester.tap(find.text('Fix'));
    await tester.pumpAndSettle();
    expect(app.visited.single, startsWith('/build/'));
    expect(app.visited.single, isNot(contains('/build/r1')));
  });

  testWidgets('create stays disabled until there is a title and a rubric', (
    tester,
  ) async {
    final app = await pumpPage(
      tester,
      const NewAssignmentPage(courseId: 'c1'),
      seed: _seed,
      size: const Size(390, 1400),
    );
    await tester.tap(find.byKey(const Key('assignments.create')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(AssignmentRepository(app.db).all), isEmpty);
    expect(app.visited, isEmpty);
  });
}
