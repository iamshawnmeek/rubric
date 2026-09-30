import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/sync_writer.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';

class AssignmentRepository {
  /// [writer] defaults to local-only writes; the app passes its sync
  /// service so writes are also queued for the server.
  new(this._db, [SyncWriter? writer]) : _writer = writer ?? LocalWriter(_db);

  final AppDatabase _db;
  final SyncWriter _writer;

  static Map<String, Object?> assignmentToWire(Assignment a) => {
    'id': a.id,
    'course_id': a.courseId,
    'title': a.title,
    'description': a.description,
    'rubric_document': jsonEncode(a.rubric.toJson()),
    'source_rubric_id': a.sourceRubricId,
    'due_on': a.dueDate?.millisecondsSinceEpoch,
    'points_possible': a.pointsPossible,
    'closed': a.closed,
    'created_on': a.createdAt.millisecondsSinceEpoch,
  };

  static Map<String, Object?> evaluationToWire(Evaluation e) => {
    'id': e.id,
    'assignment_id': e.assignmentId,
    'student_id': e.studentId,
    'status': e.status.name,
    'document': jsonEncode(e.toJson()),
    'updated_on': e.updatedAt.millisecondsSinceEpoch,
  };

  static Assignment _assignment(AssignmentRow r) => Assignment(
    id: r.id,
    courseId: r.courseId,
    title: r.title,
    description: r.description,
    rubric: Rubric.fromJson(
      jsonDecode(r.rubricDocument) as Map<String, dynamic>,
    ),
    sourceRubricId: r.sourceRubricId,
    dueDate: r.dueDate,
    pointsPossible: r.pointsPossible,
    closed: r.closed,
    createdAt: r.createdAt,
  );

  static Evaluation _evaluation(EvaluationRow r) =>
      Evaluation.fromJson(jsonDecode(r.document) as Map<String, dynamic>);

  /// Assignments for a course, soonest due first, undated last.
  Stream<List<Assignment>> watchForCourse(String courseId) {
    final q = _db.select(_db.assignments)
      ..where((a) => a.courseId.equals(courseId))
      ..orderBy([
        (a) => OrderingTerm(expression: a.dueDate, nulls: NullsOrder.last),
        (a) => OrderingTerm.desc(a.createdAt),
      ]);
    return q.watch().map((rows) => rows.map(_assignment).toList());
  }

  /// Every assignment across courses, newest first.
  Stream<List<Assignment>> watchAll() {
    final q = _db.select(_db.assignments)
      ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]);
    return q.watch().map((rows) => rows.map(_assignment).toList());
  }

  Future<List<Assignment>> all() async =>
      (await _db.select(_db.assignments).get()).map(_assignment).toList();

  Stream<Assignment?> watch(String id) =>
      (_db.select(_db.assignments)..where((a) => a.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : _assignment(r));

  Future<Assignment?> get(String id) async {
    final r = await (_db.select(
      _db.assignments,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    return r == null ? null : _assignment(r);
  }

  Future<void> save(Assignment a) =>
      _writer.upsert('assignments', assignmentToWire(a));

  /// Deletes the assignment and its evaluations (each as its own tombstone).
  Future<void> delete(String id) async {
    final evaluations = await (_db.select(
      _db.evaluations,
    )..where((e) => e.assignmentId.equals(id))).get();
    for (final e in evaluations) {
      await _writer.delete('evaluations', e.id);
    }
    await _writer.delete('assignments', id);
  }

  Stream<List<Evaluation>> watchEvaluations(String assignmentId) =>
      (_db.select(_db.evaluations)
            ..where((e) => e.assignmentId.equals(assignmentId)))
          .watch()
          .map((rows) => rows.map(_evaluation).toList());

  Future<List<Evaluation>> evaluations(String assignmentId) async =>
      (await (_db.select(
            _db.evaluations,
          )..where((e) => e.assignmentId.equals(assignmentId))).get())
          .map(_evaluation)
          .toList();

  Future<List<Evaluation>> allEvaluations() async =>
      (await _db.select(_db.evaluations).get()).map(_evaluation).toList();

  /// Every evaluation for one student across all assignments.
  Stream<List<Evaluation>> watchEvaluationsForStudent(String studentId) =>
      (_db.select(_db.evaluations)..where((e) => e.studentId.equals(studentId)))
          .watch()
          .map((rows) => rows.map(_evaluation).toList());

  /// Every evaluation for every assignment in a course.
  Stream<List<Evaluation>> watchEvaluationsForCourse(String courseId) {
    final q = _db.select(_db.evaluations).join([
      innerJoin(
        _db.assignments,
        _db.assignments.id.equalsExp(_db.evaluations.assignmentId),
      ),
    ])..where(_db.assignments.courseId.equals(courseId));
    return q.watch().map(
      (rows) =>
          rows.map((r) => _evaluation(r.readTable(_db.evaluations))).toList(),
    );
  }

  Stream<Evaluation?> watchEvaluation(String assignmentId, String studentId) =>
      (_db.select(_db.evaluations)..where(
            (e) =>
                e.assignmentId.equals(assignmentId) &
                e.studentId.equals(studentId),
          ))
          .watchSingleOrNull()
          .map((r) => r == null ? null : _evaluation(r));

  Future<Evaluation?> getEvaluation(
    String assignmentId,
    String studentId,
  ) async {
    final r =
        await (_db.select(_db.evaluations)..where(
              (e) =>
                  e.assignmentId.equals(assignmentId) &
                  e.studentId.equals(studentId),
            ))
            .getSingleOrNull();
    return r == null ? null : _evaluation(r);
  }

  /// Upserts the paper for (assignment, student). If a row for that pair is
  /// already stored under another id (data from before ids were
  /// deterministic), that id is kept so the pair never has two rows.
  Future<void> saveEvaluation(Evaluation e) async {
    final existing = await getEvaluation(e.assignmentId, e.studentId);
    final wire = evaluationToWire(e);
    if (existing != null && existing.id != e.id) {
      final doc = e.toJson()..['id'] = existing.id;
      wire
        ..['id'] = existing.id
        ..['document'] = jsonEncode(doc);
    }
    await _writer.upsert('evaluations', wire);
  }

  Future<void> saveEvaluations(Iterable<Evaluation> list) =>
      _db.transaction(() async {
        for (final e in list) {
          await saveEvaluation(e);
        }
      });

  Future<void> deleteEvaluation(String id) => _writer.delete('evaluations', id);
}
