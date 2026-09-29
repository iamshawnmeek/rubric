import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/comment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';

import '../../helpers/fixtures.dart';

/// One row in every table, linked the way real data is (so foreign keys bite).
Future<void> seedEverything(AppDatabase db) async {
  await RubricRepository(db).save(essayRubric());
  final course = Course.create(name: 'English 10', now: t0);
  await CourseRepository(db).saveCourse(course);
  final student = Student.create(
    courseId: course.id,
    firstName: 'Ada',
    lastName: 'Lovelace',
  );
  await CourseRepository(db).saveStudents([student]);
  final assignment = Assignment.create(
    courseId: course.id,
    title: 'Essay 1',
    rubric: essayRubric(),
    now: t0,
  );
  final assignments = AssignmentRepository(db);
  await assignments.save(assignment);
  await assignments.saveEvaluation(
    Evaluation.start(
      assignmentId: assignment.id,
      studentId: student.id,
      now: t0,
    ),
  );
  await CommentRepository(db).save(CommentSnippet.create('Great thesis.'));
}

/// Row counts per table, keyed by table name.
Future<Map<String, int>> rowCounts(AppDatabase db) async => {
  for (final table in db.allTables)
    table.actualTableName: await db
        .customSelect('SELECT COUNT(*) AS c FROM ${table.actualTableName}')
        .map((r) => r.read<int>('c'))
        .getSingle(),
};
