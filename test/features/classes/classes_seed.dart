import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';

import '../../helpers/fixtures.dart';

const courseId = 'c1';

final biology = Course(
  id: courseId,
  name: 'Biology',
  section: 'Period 3',
  term: 'Fall 2026',
  createdAt: t0,
);

Student student(
  String id,
  String first,
  String last, {
  String number = '',
  String email = '',
  bool archived = false,
}) => Student(
  id: id,
  courseId: courseId,
  firstName: first,
  lastName: last,
  studentNumber: number,
  email: email,
  archived: archived,
);

final Student ada = student('s1', 'Ada', 'Lovelace', number: '1001');
final Student grace = student('s2', 'Grace', 'Hopper', number: '1002');

Assignment essay({DateTime? due}) => Assignment(
  id: 'a1',
  courseId: courseId,
  title: 'Cell Essay',
  rubric: essayRubric(),
  createdAt: t0,
  dueDate: due,
);

/// Biology with Ada and Grace; with [graded], an essay Ada has been marked on.
Future<void> seedBiology(AppDatabase db, {bool graded = false}) async {
  final courses = CourseRepository(db);
  await courses.saveCourse(biology);
  await courses.saveStudents([ada, grace]);
  if (graded) {
    final assignments = AssignmentRepository(db);
    await assignments.save(essay(due: DateTime(2026, 10, 3)));
    await assignments.saveEvaluation(
      Evaluation(
        id: 'e1',
        assignmentId: 'a1',
        studentId: ada.id,
        status: EvaluationStatus.complete,
        updatedAt: t0,
      ),
    );
  }
}

/// The TextField whose hint (or text) is [text].
Finder field(String text) => find.widgetWithText(TextField, text);

Future<List<Student>> studentsIn(
  WidgetTester tester,
  AppDatabase db, {
  bool includeArchived = true,
}) async => (await tester.runAsync(
  () =>
      CourseRepository(db).students(courseId, includeArchived: includeArchived),
))!;

Future<List<Course>> allCourses(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(() => CourseRepository(db).allCourses()))!;
