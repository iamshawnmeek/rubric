import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/comment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/data/sample_data.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/scoring.dart';

import '../helpers/db.dart';

final _now = DateTime(2026, 9, 30, 10);

typedef _Snapshot = ({
  int courses,
  int students,
  int rubrics,
  int assignments,
  int evaluations,
  int snippets,
});

Future<_Snapshot> _counts(AppDatabase db) async => (
  courses: (await CourseRepository(db).allCourses()).length,
  students: (await CourseRepository(db).allStudents()).length,
  rubrics: (await RubricRepository(db).all()).length,
  assignments: (await AssignmentRepository(db).all()).length,
  evaluations: (await AssignmentRepository(db).allEvaluations()).length,
  snippets: (await CommentRepository(db).all()).length,
);

void main() {
  late AppDatabase db;

  setUp(() => db = testDatabase());
  tearDown(() => db.close());

  test('creates the demo classroom', () async {
    await loadSampleData(db, now: _now);

    expect(await _counts(db), (
      courses: 2,
      students: 48,
      rubrics: 3,
      assignments: 6,
      // Two handed-back and two mid-stack assignments of 24; the two not yet
      // due have no papers.
      evaluations: 96,
      snippets: 15,
    ));

    final rubrics = await RubricRepository(db).all();
    expect(rubrics.where((r) => r.mode == GradingMode.detailed), hasLength(1));
    expect(rubrics.every((r) => r.isReady), isTrue, reason: 'weights sum 100');

    final names = (await CourseRepository(
      db,
    ).allStudents()).map((s) => s.displayName).toSet();
    expect(names, hasLength(48), reason: 'every student name is distinct');
  });

  test('evaluations cover every status, with scores that match it', () async {
    await loadSampleData(db, now: _now);
    final assignments = {
      for (final a in await AssignmentRepository(db).all()) a.id: a,
    };
    final evaluations = await AssignmentRepository(db).allEvaluations();

    expect(
      evaluations.map((e) => e.status).toSet(),
      EvaluationStatus.values.toSet(),
    );
    for (final e in evaluations) {
      final rubric = assignments[e.assignmentId]!.rubric;
      final result = Scoring.score(rubric, e);
      switch (e.status) {
        case EvaluationStatus.complete:
          expect(result.isComplete, isTrue);
          expect(result.percent, inInclusiveRange(0, 100));
        case EvaluationStatus.inProgress:
          expect(result.scoredCount, inExclusiveRange(0, result.totalCount));
        case EvaluationStatus.notStarted ||
            EvaluationStatus.missing ||
            EvaluationStatus.excused:
          expect(e.scores, isEmpty);
      }
      expect(Scoring.derivedStatus(rubric, e), e.status);
    }
  });

  test('due dates sit around today', () async {
    await loadSampleData(db, now: _now);
    final due = (await AssignmentRepository(
      db,
    ).all()).map((a) => a.dueDate!.difference(_now).inDays).toList();
    expect(due.where((d) => d < 0), hasLength(4));
    expect(due.where((d) => d >= 0), hasLength(2));
    expect(due.every((d) => d.abs() <= 14), isTrue);
  });

  test('is idempotent', () async {
    await loadSampleData(db, now: _now);
    final first = await _counts(db);
    final firstEvaluations = await AssignmentRepository(db).allEvaluations();

    await loadSampleData(db, now: _now.add(const Duration(days: 1)));

    expect(await _counts(db), first);
    expect(
      await AssignmentRepository(db).allEvaluations(),
      unorderedEquals(firstEvaluations),
    );
  });

  test('loading again keeps the teacher’s edits to sample data', () async {
    await loadSampleData(db, now: _now);
    final repo = RubricRepository(db);
    final essay = (await repo.all()).firstWhere(
      (r) => r.title == 'Argumentative Essay',
    );
    await repo.save(essay.copyWith(title: 'My Essay Rubric'));

    await loadSampleData(db, now: _now);

    expect((await repo.get(essay.id))!.title, 'My Essay Rubric');
  });

  test(
    'is deterministic within one namespace (one teacher, two devices)',
    () async {
      final other = testDatabase();
      addTearDown(other.close);
      await loadSampleData(db, now: _now, namespace: 'demo');
      await loadSampleData(other, now: _now, namespace: 'demo');

      Future<List<String>> roster(AppDatabase d) async =>
          (await CourseRepository(
              d,
            ).allStudents()).map((s) => '${s.id}=${s.displayName}').toList()
            ..sort();
      expect(await roster(other), await roster(db));
      expect(
        await AssignmentRepository(other).allEvaluations(),
        unorderedEquals(await AssignmentRepository(db).allEvaluations()),
      );
    },
  );

  test("two teachers' demos share no row ids", () async {
    // Ids are global on the sync server: with shared ids, the second teacher
    // to sync the demo got "exists" for every row and could never upload it.
    final other = testDatabase();
    addTearDown(other.close);
    await loadSampleData(db, now: _now);
    await loadSampleData(other, now: _now);

    Future<Set<String>> ids(AppDatabase d) async => {
      for (final t in [
        'rubrics',
        'courses',
        'students',
        'assignments',
        'evaluations',
        'comment_snippets',
      ])
        for (final row in await d.customSelect('SELECT id FROM $t').get())
          row.read<String>('id'),
    };
    final mine = await ids(db);
    final theirs = await ids(other);
    expect(mine, hasLength(greaterThan(150)), reason: 'the demo loaded');
    expect(theirs, hasLength(mine.length));
    expect(mine.intersection(theirs), isEmpty);
  });

  test('loading again reuses the namespace already on the device', () async {
    await loadSampleData(db, now: _now, namespace: 'pulled');
    final before = (await CourseRepository(db).allCourses()).length;
    await loadSampleData(db, now: _now); // no namespace given: finds 'pulled'
    expect((await CourseRepository(db).allCourses()).length, before);
  });
}
