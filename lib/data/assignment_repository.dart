import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';

class AssignmentRepository {
  new(this._db);

  final AppDatabase _db;

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

  static EvaluationsCompanion _evaluationRow(Evaluation e) =>
      EvaluationsCompanion.insert(
        id: e.id,
        assignmentId: e.assignmentId,
        studentId: e.studentId,
        status: e.status.name,
        document: jsonEncode(e.toJson()),
        updatedAt: e.updatedAt,
      );

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

  Future<void> save(Assignment a) => _db
      .into(_db.assignments)
      .insertOnConflictUpdate(
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
      );

  Future<void> delete(String id) =>
      (_db.delete(_db.assignments)..where((a) => a.id.equals(id))).go();

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

  /// Upserts on (assignment, student); the stored id is kept if one exists.
  Future<void> saveEvaluation(Evaluation e) => _db
      .into(_db.evaluations)
      .insert(
        _evaluationRow(e),
        onConflict: DoUpdate.withExcluded(
          (old, excluded) => EvaluationsCompanion.custom(
            status: excluded.status,
            document: excluded.document,
            updatedAt: excluded.updatedAt,
          ),
          target: [_db.evaluations.assignmentId, _db.evaluations.studentId],
        ),
      );

  Future<void> saveEvaluations(Iterable<Evaluation> list) =>
      _db.transaction(() async {
        for (final e in list) {
          await saveEvaluation(e);
        }
      });

  Future<void> deleteEvaluation(String id) =>
      (_db.delete(_db.evaluations)..where((e) => e.id.equals(id))).go();
}
