import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/comment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';

/// Why a file could not be restored. The UI turns each into a message.
enum BackupProblem {
  /// Not JSON, or not a JSON object.
  notJson,

  /// JSON, but not a Rubric backup.
  wrongFormat,

  /// Written by a newer version of the app than this one understands.
  newerVersion,

  /// A version number this app never wrote.
  unsupportedVersion,

  /// The right format, but a record is malformed or refers to something the
  /// file does not contain.
  corrupt,
}

class BackupException implements Exception {
  const new(this.problem, [this.detail = '']);

  final BackupProblem problem;

  /// Developer-facing detail (which record, which field).
  final String detail;

  @override
  String toString() => 'BackupException(${problem.name}) $detail';
}

enum RestoreMode {
  /// Upsert by id: records in the file win, everything else on the device is
  /// kept.
  merge,

  /// Wipe the device, then import the file. One transaction: all or nothing.
  replace,
}

/// Everything in a backup file, parsed and validated.
@immutable
class BackupDocument {
  const new({
    required this.exportedAt,
    required this.rubrics,
    required this.courses,
    required this.students,
    required this.assignments,
    required this.evaluations,
    required this.commentSnippets,
    this.settings,
  });

  final DateTime exportedAt;

  /// Library rubrics and templates alike ([Rubric.isTemplate]).
  final List<Rubric> rubrics;
  final List<Course> courses;
  final List<Student> students;
  final List<Assignment> assignments;
  final List<Evaluation> evaluations;
  final List<CommentSnippet> commentSnippets;

  /// The app settings blob as the app stores it; null when not included.
  final Map<String, dynamic>? settings;

  int get templateCount => rubrics.where((r) => r.isTemplate).length;

  int get totalRecords =>
      rubrics.length +
      courses.length +
      students.length +
      assignments.length +
      evaluations.length +
      commentSnippets.length;
}

/// How a restore will land on this device, for the confirmation summary.
@immutable
class RestorePreview {
  const new({required this.incoming, required this.alreadyHere});

  final int incoming;

  /// Records in the file whose id already exists on the device — updated by a
  /// merge, gone-then-back by a replace.
  final int alreadyHere;

  int get added => incoming - alreadyHere;
}

/// Serialises the whole database (plus settings) to one versioned JSON
/// document and back.
///
/// Format: `{"format": "rubric-backup", "version": 1, "exportedAt": ISO-8601,
/// "rubrics": [...], "courses": [...], "students": [...], "assignments":
/// [...], "evaluations": [...], "commentSnippets": [...], "settings": {...}}`.
/// Rubrics and evaluations use their domain `toJson`; the rest are encoded
/// here. Bump [version] only with a reader for the old one.
class BackupService {
  new(this._db);

  static const format = 'rubric-backup';
  static const version = 1;

  final AppDatabase _db;

  // ---- Export ----

  Future<BackupDocument> snapshot({
    Map<String, dynamic>? settings,
    DateTime? now,
  }) async {
    final courses = CourseRepository(_db);
    final assignments = AssignmentRepository(_db);
    return BackupDocument(
      exportedAt: now ?? DateTime.now(),
      rubrics: await RubricRepository(_db).all(),
      courses: await courses.allCourses(),
      students: await courses.allStudents(),
      assignments: await assignments.all(),
      evaluations: await assignments.allEvaluations(),
      commentSnippets: await CommentRepository(_db).all(),
      settings: settings,
    );
  }

  /// The whole database as backup JSON. Lists are sorted by id so two
  /// backups of the same data are byte-identical apart from `exportedAt`.
  Future<String> export({
    Map<String, dynamic>? settings,
    DateTime? now,
  }) async => encode(await snapshot(settings: settings, now: now));

  static String encode(BackupDocument doc) {
    List<Map<String, dynamic>> sorted<T>(
      List<T> items,
      Map<String, dynamic> Function(T) toJson,
    ) =>
        items.map(toJson).toList()
          ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'exportedAt': doc.exportedAt.toUtc().toIso8601String(),
      'rubrics': sorted(doc.rubrics, (r) => r.toJson()),
      'courses': sorted(doc.courses, _courseToJson),
      'students': sorted(doc.students, _studentToJson),
      'assignments': sorted(doc.assignments, _assignmentToJson),
      'evaluations': sorted(doc.evaluations, (e) => e.toJson()),
      'commentSnippets': sorted(doc.commentSnippets, _snippetToJson),
      'settings': ?doc.settings,
    });
  }

  // ---- Import ----

  /// Parses and validates [source]. Throws [BackupException] describing the
  /// first problem found; never touches the database.
  static BackupDocument parse(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      throw BackupException(BackupProblem.notJson, e.message);
    }
    if (json is! Map<String, dynamic>) {
      throw const BackupException(BackupProblem.notJson);
    }
    final map = json;
    if (json['format'] != format) {
      throw BackupException(BackupProblem.wrongFormat, '${json['format']}');
    }
    final v = json['version'];
    if (v is! int || v < 1) {
      throw BackupException(BackupProblem.unsupportedVersion, '$v');
    }
    if (v > version) {
      throw BackupException(BackupProblem.newerVersion, '$v');
    }

    final doc = _guard('document', () {
      List<T> list<T>(
        String key,
        T Function(Map<String, dynamic>) fromJson,
      ) => [
        for (final (i, e) in (map[key] as List<dynamic>? ?? const []).indexed)
          _guard('$key[$i]', () => fromJson(e as Map<String, dynamic>)),
      ];
      return BackupDocument(
        exportedAt: DateTime.parse(map['exportedAt'] as String).toLocal(),
        rubrics: list('rubrics', Rubric.fromJson),
        courses: list('courses', _courseFromJson),
        students: list('students', _studentFromJson),
        assignments: list('assignments', _assignmentFromJson),
        evaluations: list('evaluations', Evaluation.fromJson),
        commentSnippets: list('commentSnippets', _snippetFromJson),
        settings: map['settings'] as Map<String, dynamic>?,
      );
    });
    _checkReferences(doc);
    return doc;
  }

  /// Counts how many of [doc]'s records already exist here.
  Future<RestorePreview> preview(BackupDocument doc) async {
    Future<int> existing<T extends HasResultSet, R>(
      ResultSetImplementation<T, R> table,
      GeneratedColumn<String> id,
      Iterable<String> ids,
    ) async {
      final wanted = ids.toSet();
      if (wanted.isEmpty) return 0;
      final q = _db.selectOnly(table)
        ..addColumns([id])
        ..where(id.isIn(wanted));
      return (await q.get()).length;
    }

    final here = [
      await existing(_db.rubrics, _db.rubrics.id, doc.rubrics.map((r) => r.id)),
      await existing(_db.courses, _db.courses.id, doc.courses.map((c) => c.id)),
      await existing(
        _db.students,
        _db.students.id,
        doc.students.map((s) => s.id),
      ),
      await existing(
        _db.assignments,
        _db.assignments.id,
        doc.assignments.map((a) => a.id),
      ),
      await existing(
        _db.evaluations,
        _db.evaluations.id,
        doc.evaluations.map((e) => e.id),
      ),
      await existing(
        _db.commentSnippets,
        _db.commentSnippets.id,
        doc.commentSnippets.map((c) => c.id),
      ),
    ].fold(0, (a, b) => a + b);
    return RestorePreview(incoming: doc.totalRecords, alreadyHere: here);
  }

  /// Writes [doc] into the database in one transaction.
  Future<void> restore(BackupDocument doc, {required RestoreMode mode}) =>
      _db.transaction(() async {
        if (mode == RestoreMode.replace) {
          // Children first, although the cascades would cover them.
          await _db.delete(_db.evaluations).go();
          await _db.delete(_db.assignments).go();
          await _db.delete(_db.students).go();
          await _db.delete(_db.courses).go();
          await _db.delete(_db.rubrics).go();
          await _db.delete(_db.commentSnippets).go();
        } else {
          // An evaluation is unique per (assignment, student). If this device
          // graded the same pair under a different id, the file's copy wins.
          for (final e in doc.evaluations) {
            await (_db.delete(_db.evaluations)..where(
                  (t) =>
                      t.assignmentId.equals(e.assignmentId) &
                      t.studentId.equals(e.studentId) &
                      t.id.equals(e.id).not(),
                ))
                .go();
          }
        }

        // Parents before children so foreign keys always resolve. Rows are
        // written directly (not via the repositories) so timestamps are kept
        // exactly as backed up.
        await _db.batch((b) {
          b
            ..insertAllOnConflictUpdate(_db.rubrics, [
              for (final r in doc.rubrics)
                RubricsCompanion.insert(
                  id: r.id,
                  title: r.title,
                  subject: Value(r.subject),
                  isTemplate: Value(r.isTemplate),
                  archived: Value(r.archived),
                  document: jsonEncode(r.toJson()),
                  createdAt: r.createdAt,
                  updatedAt: r.updatedAt,
                ),
            ])
            ..insertAllOnConflictUpdate(_db.courses, [
              for (final c in doc.courses)
                CoursesCompanion.insert(
                  id: c.id,
                  name: c.name,
                  section: Value(c.section),
                  term: Value(c.term),
                  archived: Value(c.archived),
                  createdAt: c.createdAt,
                ),
            ])
            ..insertAllOnConflictUpdate(_db.students, [
              for (final s in doc.students)
                StudentsCompanion.insert(
                  id: s.id,
                  courseId: s.courseId,
                  firstName: s.firstName,
                  lastName: Value(s.lastName),
                  studentNumber: Value(s.studentNumber),
                  email: Value(s.email),
                  notes: Value(s.notes),
                  archived: Value(s.archived),
                ),
            ])
            ..insertAllOnConflictUpdate(_db.assignments, [
              for (final a in doc.assignments)
                AssignmentsCompanion.insert(
                  id: a.id,
                  courseId: a.courseId,
                  title: a.title,
                  description: Value(a.description),
                  rubricDocument: jsonEncode(a.rubric.toJson()),
                  sourceRubricId: Value(a.sourceRubricId),
                  dueDate: Value(a.dueDate),
                  pointsPossible: Value(a.pointsPossible),
                  closed: Value(a.closed),
                  createdAt: a.createdAt,
                ),
            ])
            ..insertAllOnConflictUpdate(_db.evaluations, [
              for (final e in doc.evaluations)
                EvaluationsCompanion.insert(
                  id: e.id,
                  assignmentId: e.assignmentId,
                  studentId: e.studentId,
                  status: e.status.name,
                  document: jsonEncode(e.toJson()),
                  updatedAt: e.updatedAt,
                ),
            ])
            ..insertAllOnConflictUpdate(_db.commentSnippets, [
              for (final c in doc.commentSnippets)
                CommentSnippetsCompanion.insert(
                  id: c.id,
                  body: c.text,
                  category: Value(c.category),
                  useCount: Value(c.useCount),
                ),
            ]);
        });
      });

  // ---- Validation ----

  static T _guard<T>(String where, T Function() read) {
    try {
      return read();
    } on BackupException {
      rethrow;
    } on Object catch (e) {
      throw BackupException(BackupProblem.corrupt, '$where: $e');
    }
  }

  /// Every reference must resolve inside the file itself, so a restore can
  /// never half-apply on a foreign-key failure. Ids must be unique per kind.
  static void _checkReferences(BackupDocument doc) {
    Set<String> ids(String kind, Iterable<String> all) {
      final set = <String>{};
      for (final id in all) {
        if (!set.add(id)) {
          throw BackupException(BackupProblem.corrupt, 'duplicate $kind $id');
        }
      }
      return set;
    }

    void check(String what, {required bool ok}) {
      if (!ok) throw BackupException(BackupProblem.corrupt, what);
    }

    ids('rubric', doc.rubrics.map((r) => r.id));
    ids('snippet', doc.commentSnippets.map((c) => c.id));
    final courses = ids('course', doc.courses.map((c) => c.id));
    final students = ids('student', doc.students.map((s) => s.id));
    final assignments = ids('assignment', doc.assignments.map((a) => a.id));
    ids('evaluation', doc.evaluations.map((e) => e.id));

    for (final s in doc.students) {
      check('student ${s.id} course', ok: courses.contains(s.courseId));
    }
    for (final a in doc.assignments) {
      check('assignment ${a.id} course', ok: courses.contains(a.courseId));
    }
    final pairs = <(String, String)>{};
    for (final e in doc.evaluations) {
      check(
        'evaluation ${e.id} assignment',
        ok: assignments.contains(e.assignmentId),
      );
      check('evaluation ${e.id} student', ok: students.contains(e.studentId));
      check(
        'evaluation ${e.id} duplicate',
        ok: pairs.add((e.assignmentId, e.studentId)),
      );
    }
  }

  // ---- Codecs for records without a domain toJson ----

  static DateTime _date(Object? v) => DateTime.parse(v! as String).toLocal();
  static String _iso(DateTime d) => d.toUtc().toIso8601String();

  static Map<String, dynamic> _courseToJson(Course c) => {
    'id': c.id,
    'name': c.name,
    'section': c.section,
    'term': c.term,
    'archived': c.archived,
    'createdAt': _iso(c.createdAt),
  };

  static Course _courseFromJson(Map<String, dynamic> j) => Course(
    id: j['id'] as String,
    name: j['name'] as String,
    section: j['section'] as String? ?? '',
    term: j['term'] as String? ?? '',
    archived: j['archived'] as bool? ?? false,
    createdAt: _date(j['createdAt']),
  );

  static Map<String, dynamic> _studentToJson(Student s) => {
    'id': s.id,
    'courseId': s.courseId,
    'firstName': s.firstName,
    'lastName': s.lastName,
    'studentNumber': s.studentNumber,
    'email': s.email,
    'notes': s.notes,
    'archived': s.archived,
  };

  static Student _studentFromJson(Map<String, dynamic> j) => Student(
    id: j['id'] as String,
    courseId: j['courseId'] as String,
    firstName: j['firstName'] as String,
    lastName: j['lastName'] as String? ?? '',
    studentNumber: j['studentNumber'] as String? ?? '',
    email: j['email'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    archived: j['archived'] as bool? ?? false,
  );

  static Map<String, dynamic> _assignmentToJson(Assignment a) => {
    'id': a.id,
    'courseId': a.courseId,
    'title': a.title,
    'description': a.description,
    'rubric': a.rubric.toJson(),
    'sourceRubricId': a.sourceRubricId,
    'dueDate': a.dueDate == null ? null : _iso(a.dueDate!),
    'pointsPossible': a.pointsPossible,
    'closed': a.closed,
    'createdAt': _iso(a.createdAt),
  };

  static Assignment _assignmentFromJson(Map<String, dynamic> j) => Assignment(
    id: j['id'] as String,
    courseId: j['courseId'] as String,
    title: j['title'] as String,
    description: j['description'] as String? ?? '',
    rubric: Rubric.fromJson(j['rubric'] as Map<String, dynamic>),
    sourceRubricId: j['sourceRubricId'] as String?,
    dueDate: j['dueDate'] == null ? null : _date(j['dueDate']),
    pointsPossible: (j['pointsPossible'] as num?)?.toDouble() ?? 100,
    closed: j['closed'] as bool? ?? false,
    createdAt: _date(j['createdAt']),
  );

  static Map<String, dynamic> _snippetToJson(CommentSnippet c) => {
    'id': c.id,
    'text': c.text,
    'category': c.category,
    'useCount': c.useCount,
  };

  static CommentSnippet _snippetFromJson(Map<String, dynamic> j) =>
      CommentSnippet(
        id: j['id'] as String,
        text: j['text'] as String,
        category: j['category'] as String? ?? '',
        useCount: (j['useCount'] as num?)?.toInt() ?? 0,
      );
}
