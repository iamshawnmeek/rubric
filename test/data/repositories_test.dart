import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/comment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';

import '../helpers/db.dart';
import '../helpers/fixtures.dart';

void main() {
  late AppDatabase db;
  late RubricRepository rubrics;
  late CourseRepository courses;
  late AssignmentRepository assignments;
  late CommentRepository comments;

  setUp(() {
    db = testDatabase();
    rubrics = RubricRepository(db);
    courses = CourseRepository(db);
    assignments = AssignmentRepository(db);
    comments = CommentRepository(db);
  });

  tearDown(() => db.close());

  test('rubrics round-trip and stamp updatedAt', () async {
    final saved = await rubrics.save(
      essayRubric(),
      now: t0.add(const Duration(days: 1)),
    );
    expect(saved.updatedAt, t0.add(const Duration(days: 1)));
    expect(await rubrics.get('r1'), saved);
    expect(await rubrics.watchAll().first, [saved]);
  });

  test('templates and archived rubrics are listed separately', () async {
    await rubrics.save(essayRubric());
    await rubrics.save(essayRubric().duplicate(isTemplate: true));
    await rubrics.setArchived('r1', archived: true);
    expect(await rubrics.watchAll().first, isEmpty);
    expect(await rubrics.watchAll(archived: true).first, hasLength(1));
    expect(await rubrics.watchAll(templates: true).first, hasLength(1));
  });

  Future<(Course, List<Student>, Assignment)> seedCourse() async {
    final course = Course.create(name: 'English 10', now: t0);
    await courses.saveCourse(course);
    final roster = [
      Student.create(
        courseId: course.id,
        firstName: 'Ada',
        lastName: 'Lovelace',
      ),
      Student.create(
        courseId: course.id,
        firstName: 'alan',
        lastName: 'turing',
      ),
      Student.create(
        courseId: course.id,
        firstName: 'Grace',
        lastName: 'Hopper',
      ),
    ];
    await courses.saveStudents(roster);
    final assignment = Assignment.create(
      courseId: course.id,
      title: 'Essay 1',
      rubric: essayRubric(),
      now: t0,
    );
    await assignments.save(assignment);
    return (course, roster, assignment);
  }

  test('students sort by last name, case-insensitively', () async {
    final (course, _, _) = await seedCourse();
    final names = (await courses.watchStudents(course.id).first).map(
      (s) => s.lastName,
    );
    expect(names, ['Hopper', 'Lovelace', 'turing']);
    expect(await courses.watchStudentCounts().first, {course.id: 3});
  });

  test('evaluations upsert on (assignment, student)', () async {
    final (_, roster, assignment) = await seedCourse();
    final first = Evaluation.start(
      assignmentId: assignment.id,
      studentId: roster.first.id,
      now: t0,
    );
    await assignments.saveEvaluation(first);
    // A second Evaluation object for the same pair (e.g. created on another
    // screen) must update the existing row, not insert a duplicate.
    final second = Evaluation.start(
      assignmentId: assignment.id,
      studentId: roster.first.id,
      now: t0,
    ).withScore('o1', const PercentScore(90));
    await assignments.saveEvaluation(second);
    final stored = await assignments.evaluations(assignment.id);
    expect(stored, hasLength(1));
    expect(stored.single.scores['o1'], const PercentScore(90));
  });

  test(
    'assignment keeps its rubric snapshot when the library rubric changes',
    () async {
      final (_, _, assignment) = await seedCourse();
      await rubrics.save(essayRubric().copyWith(title: 'Renamed'));
      expect((await assignments.get(assignment.id))!.rubric.title, 'Essay');
    },
  );

  test(
    'deleting a course cascades to students, assignments and evaluations',
    () async {
      final (course, roster, assignment) = await seedCourse();
      await assignments.saveEvaluation(
        Evaluation.start(
          assignmentId: assignment.id,
          studentId: roster.first.id,
        ),
      );
      await courses.deleteCourse(course.id);
      expect(await courses.allStudents(), isEmpty);
      expect(await assignments.all(), isEmpty);
      expect(await assignments.allEvaluations(), isEmpty);
    },
  );

  test('course evaluations join through assignments', () async {
    final (course, roster, assignment) = await seedCourse();
    await assignments.saveEvaluations([
      for (final s in roster)
        Evaluation.start(assignmentId: assignment.id, studentId: s.id),
    ]);
    expect(
      await assignments.watchEvaluationsForCourse(course.id).first,
      hasLength(3),
    );
    expect(await assignments.watchEvaluationsForCourse('other').first, isEmpty);
  });

  test('comment bank orders by use', () async {
    final a = CommentSnippet.create('Great thesis');
    final b = CommentSnippet.create('Cite your sources');
    await comments.save(a);
    await comments.save(b);
    await comments.recordUse(b.id);
    expect((await comments.watchAll().first).first.id, b.id);
  });
}
