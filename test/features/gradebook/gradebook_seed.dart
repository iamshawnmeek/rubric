import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';

import '../../helpers/fixtures.dart';

const courseId = 'c1';

final course = Course(id: courseId, name: 'Period 3 English', createdAt: t0);

const ada = Student(
  id: 's1',
  courseId: courseId,
  firstName: 'Ada',
  lastName: 'Lovelace',
  studentNumber: '1001',
  email: 'ada@example.com',
);
const alan = Student(
  id: 's2',
  courseId: courseId,
  firstName: 'Alan',
  lastName: 'Turing',
);
const grace = Student(
  id: 's3',
  courseId: courseId,
  firstName: 'Grace',
  lastName: 'Hopper',
);

final essay1 = Assignment(
  id: 'a1',
  courseId: courseId,
  title: 'Essay 1',
  rubric: essayRubric(),
  dueDate: DateTime(2026, 9, 5),
  createdAt: t0,
);
final essay2 = Assignment(
  id: 'a2',
  courseId: courseId,
  title: 'Essay 2',
  rubric: essayRubric(),
  dueDate: DateTime(2026, 9, 12),
  createdAt: t0,
);

/// Every objective at [p]% — so the grade of record is exactly [p].
Evaluation gradedAt(String studentId, String assignmentId, double p) =>
    Evaluation(
      id: 'e-$studentId-$assignmentId',
      assignmentId: assignmentId,
      studentId: studentId,
      status: EvaluationStatus.complete,
      scores: {
        for (final o in ['o1', 'o2', 'o3']) o: PercentScore(p),
      },
      updatedAt: t0,
    );

Evaluation markedAs(
  String studentId,
  String assignmentId,
  EvaluationStatus status,
) => Evaluation(
  id: 'e-$studentId-$assignmentId',
  assignmentId: assignmentId,
  studentId: studentId,
  status: status,
  updatedAt: t0,
);

/// Ada: 90 then 70 (average 80). Alan: 60 then missing (average 30).
/// Grace: excused then not graded (no average).
Future<void> seedClass(
  AppDatabase db, {
  List<Student> students = const [ada, alan, grace],
  bool withAssignments = true,
  List<Evaluation>? evaluations,
}) async {
  final courses = CourseRepository(db);
  final assignments = AssignmentRepository(db);
  await courses.saveCourse(course);
  await courses.saveStudents(students);
  if (!withAssignments) return;
  await assignments.save(essay1);
  await assignments.save(essay2);
  await assignments.saveEvaluations(
    evaluations ??
        [
          gradedAt('s1', 'a1', 90),
          gradedAt('s1', 'a2', 70),
          gradedAt('s2', 'a1', 60),
          markedAs('s2', 'a2', EvaluationStatus.missing),
          markedAs('s3', 'a1', EvaluationStatus.excused),
        ],
  );
}
