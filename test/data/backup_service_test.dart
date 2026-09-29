import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/backup_service.dart';
import 'package:rubric/data/comment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';

import '../helpers/db.dart';
import '../helpers/fixtures.dart';

final _exportedAt = DateTime(2026, 9, 29, 8, 30);

/// A bit of everything: a rubric and a template, a course with an active and
/// an archived student, an assignment, graded work and a comment snippet.
Future<void> _seed(AppDatabase db) async {
  await RubricRepository(db).save(essayRubric(), now: t0);
  await RubricRepository(db).save(
    essayRubric(mode: GradingMode.detailed)
        .duplicate(title: 'Lab report template', isTemplate: true, now: t0),
    now: t0,
  );
  final courses = CourseRepository(db);
  await courses.saveCourse(
    Course(id: 'c1', name: 'English 10', section: 'P3', createdAt: t0),
  );
  await courses.saveStudents([
    const Student(
      id: 's1',
      courseId: 'c1',
      firstName: 'Ada',
      lastName: 'Lovelace',
      studentNumber: '001',
      email: 'ada@example.com',
      notes: 'Front row',
    ),
    const Student(
      id: 's2',
      courseId: 'c1',
      firstName: 'Zed',
      lastName: 'Young',
      archived: true,
    ),
  ]);
  final assignments = AssignmentRepository(db);
  await assignments.save(
    Assignment(
      id: 'a1',
      courseId: 'c1',
      title: 'Essay',
      rubric: essayRubric(),
      sourceRubricId: 'r1',
      dueDate: DateTime(2026, 9, 12),
      pointsPossible: 50,
      createdAt: t0,
    ),
  );
  await assignments.saveEvaluations([
    eval(const {
      'o1': PercentScore(80),
      'o3': PercentScore(95),
    }, penalty: 5).copyWith(
      comment: 'Nice, "really"\nnice',
      objectiveComments: {'o1': 'commas'},
      late: true,
      updatedAt: t0,
    ),
    eval(const {}, student: 's2', status: EvaluationStatus.excused),
  ]);
  await CommentRepository(db)
      .save(const CommentSnippet(id: 'k1', text: 'Great thesis', useCount: 3));
}

void main() {
  late AppDatabase db;
  setUp(() => db = testDatabase());
  tearDown(() => db.close());

  Future<String> backupOf(AppDatabase from) =>
      BackupService(from)
          .export(settings: const {'teacherName': 'Ms. W'}, now: _exportedAt);

  group('export', () {
    test(
      'is a versioned rubric-backup document with everything in it',
      () async {
        await _seed(db);
        final json = jsonDecode(await backupOf(db)) as Map<String, dynamic>;
        expect(json['format'], 'rubric-backup');
        expect(json['version'], 1);
        expect(
          DateTime.parse(json['exportedAt'] as String),
          _exportedAt.toUtc(),
        );
        expect(json['rubrics'], hasLength(2));
        expect(json['courses'], hasLength(1));
        expect(json['students'], hasLength(2));
        expect(json['assignments'], hasLength(1));
        expect(json['evaluations'], hasLength(2));
        expect(json['commentSnippets'], hasLength(1));
        expect(json['settings'], {'teacherName': 'Ms. W'});
      },
    );
  });

  group('round trip', () {
    test('restoring into a fresh database reproduces the original', () async {
      await _seed(db);
      final original = await backupOf(db);

      final fresh = testDatabase();
      addTearDown(fresh.close);
      await BackupService(fresh)
          .restore(BackupService.parse(original), mode: RestoreMode.replace);

      expect(await backupOf(fresh), original);

      // And at the domain level, not just the serialisation.
      final a = await BackupService(db).snapshot();
      final b = await BackupService(fresh).snapshot();
      expect(b.rubrics.sortedBy((r) => r.id), a.rubrics.sortedBy((r) => r.id));
      expect(b.courses, a.courses);
      expect(
        b.students.sortedBy((s) => s.id),
        a.students.sortedBy((s) => s.id),
      );
      expect(b.assignments, a.assignments);
      expect(
        b.evaluations.sortedBy((e) => e.id),
        a.evaluations.sortedBy((e) => e.id),
      );
      expect(b.commentSnippets, a.commentSnippets);
    });

    test('parse returns the settings blob untouched', () async {
      await _seed(db);
      final doc = BackupService.parse(await backupOf(db));
      expect(doc.settings, {'teacherName': 'Ms. W'});
      expect(doc.templateCount, 1);
      expect(doc.totalRecords, 2 + 1 + 2 + 1 + 2 + 1);
    });
  });

  group('parse rejects', () {
    Matcher problem(BackupProblem p) =>
        throwsA(isA<BackupException>().having((e) => e.problem, 'problem', p));

    Map<String, dynamic> valid() => {
      'format': 'rubric-backup',
      'version': 1,
      'exportedAt': '2026-09-29T08:30:00.000Z',
    };

    test('text that is not JSON', () {
      expect(
        () => BackupService.parse('not json'),
        problem(BackupProblem.notJson),
      );
      expect(
        () => BackupService.parse('[1, 2]'),
        problem(BackupProblem.notJson),
      );
    });

    test('JSON in another format', () {
      expect(
        () => BackupService.parse(jsonEncode({...valid(), 'format': 'other'})),
        problem(BackupProblem.wrongFormat),
      );
      expect(
        () => BackupService.parse(jsonEncode({'version': 1})),
        problem(BackupProblem.wrongFormat),
      );
    });

    test('a newer or unknown version', () {
      expect(
        () => BackupService.parse(jsonEncode({...valid(), 'version': 2})),
        problem(BackupProblem.newerVersion),
      );
      for (final v in [0, '1', null]) {
        expect(
          () => BackupService.parse(jsonEncode({...valid(), 'version': v})),
          problem(BackupProblem.unsupportedVersion),
          reason: 'version $v',
        );
      }
    });

    test('malformed records', () {
      expect(
        () => BackupService.parse(
          jsonEncode({
            ...valid(),
            'courses': [
              {'id': 'c1'},
            ],
          }),
        ),
        problem(BackupProblem.corrupt),
      );
      expect(
        () => BackupService.parse(jsonEncode({...valid(), 'exportedAt': 5})),
        problem(BackupProblem.corrupt),
      );
    });

    test('references the file does not contain, and duplicate ids', () async {
      await _seed(db);
      final json = jsonDecode(await backupOf(db)) as Map<String, dynamic>;

      final orphan = Map<String, dynamic>.of(json)..['courses'] = <Object>[];
      expect(
        () => BackupService.parse(jsonEncode(orphan)),
        problem(BackupProblem.corrupt),
      );

      final dup = Map<String, dynamic>.of(json)
        ..['rubrics'] = [
          ...json['rubrics'] as List,
          (json['rubrics'] as List)[0],
        ];
      expect(
        () => BackupService.parse(jsonEncode(dup)),
        problem(BackupProblem.corrupt),
      );
    });

    test('a rejected file never touches the database', () async {
      await _seed(db);
      final before = await backupOf(db);
      expect(() => BackupService.parse('{}'), throwsA(isA<BackupException>()));
      expect(await backupOf(db), before);
    });
  });

  group('restore modes', () {
    late BackupDocument backup;

    setUp(() async {
      final source = testDatabase();
      addTearDown(source.close);
      await _seed(source);
      backup = BackupService.parse(await backupOf(source));

      // This device: an older copy of the course, a rubric the backup does
      // not have, and s1's essay graded under a different evaluation id.
      await CourseRepository(db)
          .saveCourse(Course(id: 'c1', name: 'Old name', createdAt: t0));
      await CourseRepository(db).saveStudent(
        const Student(id: 's1', courseId: 'c1', firstName: 'Ada', lastName: ''),
      );
      await AssignmentRepository(db).save(
        Assignment(
          id: 'a1',
          courseId: 'c1',
          title: 'Essay',
          rubric: essayRubric(),
          createdAt: t0,
        ),
      );
      await AssignmentRepository(db).saveEvaluation(
        Evaluation(
          id: 'local-eval',
          assignmentId: 'a1',
          studentId: 's1',
          overridePercent: 12,
          updatedAt: t0,
        ),
      );
      await RubricRepository(db).save(
        Rubric(id: 'mine', title: 'Only here', createdAt: t0, updatedAt: t0),
        now: t0,
      );
    });

    test('preview counts what is new and what already exists', () async {
      final preview = await BackupService(db).preview(backup);
      // c1, s1, a1 exist by id; the local evaluation has a different id.
      expect(preview.alreadyHere, 3);
      expect(preview.incoming, backup.totalRecords);
      expect(preview.added, backup.totalRecords - 3);
    });

    test('merge upserts by id and keeps everything else', () async {
      await BackupService(db).restore(backup, mode: RestoreMode.merge);

      expect(await RubricRepository(db).get('mine'), isNotNull);
      expect(await RubricRepository(db).get('r1'), isNotNull);
      expect((await CourseRepository(db).getCourse('c1'))!.name, 'English 10');
      expect((await AssignmentRepository(db).get('a1'))!.pointsPossible, 50);

      // The file's evaluation replaced the local one for the same pair.
      final evaluation = await AssignmentRepository(db)
          .getEvaluation('a1', 's1');
      expect(evaluation!.id, 'e-s1');
      expect(evaluation.overridePercent, isNull);
      expect(await AssignmentRepository(db).allEvaluations(), hasLength(2));
    });

    test('replace wipes the device first', () async {
      await BackupService(db).restore(backup, mode: RestoreMode.replace);

      expect(await RubricRepository(db).get('mine'), isNull);
      final json = jsonDecode(await backupOf(db)) as Map<String, dynamic>;
      final expected =
          jsonDecode(BackupService.encode(backup)) as Map<String, dynamic>;
      for (final key in [
        'rubrics',
        'courses',
        'students',
        'assignments',
        'evaluations',
        'commentSnippets',
      ]) {
        expect(json[key], expected[key], reason: key);
      }
    });

    test('replace is all-or-nothing', () async {
      final before = await backupOf(db);
      // Valid on its own, but a student points at a course the database will
      // not have after the wipe; the foreign key fails mid-transaction.
      final broken = BackupDocument(
        exportedAt: _exportedAt,
        rubrics: backup.rubrics,
        courses: const [],
        students: backup.students,
        assignments: const [],
        evaluations: const [],
        commentSnippets: const [],
      );
      await expectLater(
        BackupService(db).restore(broken, mode: RestoreMode.replace),
        throwsA(anything),
      );
      expect(await backupOf(db), before);
    });
  });
}
