import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/comment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';

import '../../helpers/fixtures.dart';

/// Roster deliberately inserted out of order; [compareStudents] order is
/// Ada Lovelace, Bob Lovelace, Alan Turing, Cara Zed.
final gradingRoster = [
  const Student(
    id: 's-cara',
    courseId: 'c1',
    firstName: 'Cara',
    lastName: 'Zed',
  ),
  const Student(
    id: 's-ada',
    courseId: 'c1',
    firstName: 'Ada',
    lastName: 'Lovelace',
  ),
  const Student(
    id: 's-alan',
    courseId: 'c1',
    firstName: 'Alan',
    lastName: 'Turing',
  ),
  const Student(
    id: 's-bob',
    courseId: 'c1',
    firstName: 'Bob',
    lastName: 'Lovelace',
  ),
];

const rosterOrder = ['s-ada', 's-bob', 's-alan', 's-cara'];

/// Seeds course c1, [gradingRoster], and assignment a1 on [essayRubric].
Future<void> seedGrading(
  AppDatabase db, {
  GradingMode mode = GradingMode.simple,
  List<Evaluation> evaluations = const [],
  List<CommentSnippet> snippets = const [],
  List<Student>? students,
}) async {
  final courses = CourseRepository(db);
  await courses.saveCourse(Course(id: 'c1', name: 'English 10', createdAt: t0));
  await courses.saveStudents(students ?? gradingRoster);
  final assignments = AssignmentRepository(db);
  await assignments.save(
    Assignment(
      id: 'a1',
      courseId: 'c1',
      title: 'Persuasive Essay',
      rubric: essayRubric(mode: mode),
      createdAt: t0,
    ),
  );
  await assignments.saveEvaluations(evaluations);
  final comments = CommentRepository(db);
  for (final s in snippets) {
    await comments.save(s);
  }
}

/// A fully scored evaluation for [studentId] at [percent] on every objective.
Evaluation gradedEval(String studentId, double percent) => Evaluation(
  id: 'e-$studentId',
  assignmentId: 'a1',
  studentId: studentId,
  status: EvaluationStatus.complete,
  scores: {
    for (final o in ['o1', 'o2', 'o3']) o: PercentScore(percent),
  },
  updatedAt: t0,
);
