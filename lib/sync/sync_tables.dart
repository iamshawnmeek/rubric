import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rubric/data/database.dart';
import 'package:zonai_sync/zonai_sync.dart';
import 'package:zonai_sync_drift/zonai_sync_drift.dart';

/// The synced tables, parents first. Mirrors server/ (tool/gen/server_schema.py).
///
/// Evaluations use field-merge (the default) so two devices grading different
/// objectives of the same paper both keep their marks — the scores live in
/// one JSON document per paper, and the last writer of that document wins
/// field-for-field, which is why graders should not grade the same paper on
/// two devices at once.
const syncTables = [
  SyncTable('rubrics'),
  SyncTable('comment_snippets'),
  SyncTable('courses'),
  SyncTable(
    'students',
    parents: ['courses'],
    references: {'course_id': 'courses'},
  ),
  SyncTable(
    'assignments',
    parents: ['courses'],
    references: {'course_id': 'courses'},
  ),
  SyncTable(
    'evaluations',
    parents: ['assignments', 'students'],
    references: {'assignment_id': 'assignments', 'student_id': 'students'},
  ),
];

// ---- wire helpers: zonai sends booleans as 0/1 and dates as epoch ms ----

bool wireBool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

int? wireMillis(Object? v) => switch (v) {
  null => null,
  final int ms => ms,
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? DateTime.parse(s).millisecondsSinceEpoch,
  _ => null,
};

DateTime? wireDate(Object? v) {
  final ms = wireMillis(v);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

String wireText(Object? v) => v?.toString() ?? '';

/// Common shape of Rubric's DriftSyncTables: the owner column is added on
/// read from whoever is signed in (it is implied locally — one account per
/// device), and reads/writes are by id.
abstract class _RubricSyncTable implements DriftSyncTable {
  new(this.db, this.owner);

  final AppDatabase db;
  final String? Function() owner;

  Map<String, Object?> withOwner(Map<String, Object?> wire) => {
    ...wire,
    'owner_id': owner(),
  };
}

final class RubricsSync extends _RubricSyncTable {
  new(super.db, super.owner);

  @override
  String get name => 'rubrics';

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final r = await (db.select(
      db.rubrics,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    return withOwner({
      'id': r.id,
      'title': r.title,
      'subject': r.subject,
      'is_template': r.isTemplate,
      'archived': r.archived,
      'document': r.document,
      'created_on': r.createdAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> write(Map<String, Object?> w) async {
    final document = wireText(w['document']);
    // The domain's own edit time lives in the document.
    final updatedAt =
        wireDate((jsonDecode(document) as Map<String, Object?>)['updatedAt']) ??
        DateTime.now();
    await db
        .into(db.rubrics)
        .insertOnConflictUpdate(
          RubricsCompanion.insert(
            id: w['id']! as String,
            title: wireText(w['title']),
            subject: Value(wireText(w['subject'])),
            isTemplate: Value(wireBool(w['is_template'])),
            archived: Value(wireBool(w['archived'])),
            document: document,
            createdAt: wireDate(w['created_on']) ?? updatedAt,
            updatedAt: updatedAt,
          ),
        );
  }

  @override
  Future<void> delete(String id) =>
      (db.delete(db.rubrics)..where((t) => t.id.equals(id))).go();

  @override
  Future<List<String>> ids() async =>
      (await db.select(db.rubrics).get()).map((r) => r.id).toList();

  @override
  Future<void> clear() => db.delete(db.rubrics).go();
}

final class CommentSnippetsSync extends _RubricSyncTable {
  new(super.db, super.owner);

  @override
  String get name => 'comment_snippets';

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final r = await (db.select(
      db.commentSnippets,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    return withOwner({
      'id': r.id,
      'body': r.body,
      'category': r.category,
      'use_count': r.useCount,
    });
  }

  @override
  Future<void> write(Map<String, Object?> w) => db
      .into(db.commentSnippets)
      .insertOnConflictUpdate(
        CommentSnippetsCompanion.insert(
          id: w['id']! as String,
          body: wireText(w['body']),
          category: Value(wireText(w['category'])),
          useCount: Value(wireMillis(w['use_count']) ?? 0),
        ),
      );

  @override
  Future<void> delete(String id) =>
      (db.delete(db.commentSnippets)..where((t) => t.id.equals(id))).go();

  @override
  Future<List<String>> ids() async =>
      (await db.select(db.commentSnippets).get()).map((r) => r.id).toList();

  @override
  Future<void> clear() => db.delete(db.commentSnippets).go();
}

final class CoursesSync extends _RubricSyncTable {
  new(super.db, super.owner);

  @override
  String get name => 'courses';

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final r = await (db.select(
      db.courses,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    return withOwner({
      'id': r.id,
      'name': r.name,
      'section': r.section,
      'term': r.term,
      'archived': r.archived,
      'created_on': r.createdAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> write(Map<String, Object?> w) => db
      .into(db.courses)
      .insertOnConflictUpdate(
        CoursesCompanion.insert(
          id: w['id']! as String,
          name: wireText(w['name']),
          section: Value(wireText(w['section'])),
          term: Value(wireText(w['term'])),
          archived: Value(wireBool(w['archived'])),
          createdAt: wireDate(w['created_on']) ?? DateTime.now(),
        ),
      );

  @override
  Future<void> delete(String id) =>
      (db.delete(db.courses)..where((t) => t.id.equals(id))).go();

  @override
  Future<List<String>> ids() async =>
      (await db.select(db.courses).get()).map((r) => r.id).toList();

  @override
  Future<void> clear() => db.delete(db.courses).go();
}

/// Children skip a pulled row whose parent is not held locally (the parent
/// was deleted on another device); writing it would violate the local
/// foreign key and stall the pull of the whole table.
Future<bool> _exists(AppDatabase db, String table, String id) async =>
    (await db
        .customSelect(
          'SELECT 1 FROM $table WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull()) !=
    null;

final class StudentsSync extends _RubricSyncTable {
  new(super.db, super.owner);

  @override
  String get name => 'students';

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final r = await (db.select(
      db.students,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    return withOwner({
      'id': r.id,
      'course_id': r.courseId,
      'first_name': r.firstName,
      'last_name': r.lastName,
      'student_number': r.studentNumber,
      'email': r.email,
      'notes': r.notes,
      'archived': r.archived,
    });
  }

  @override
  Future<void> write(Map<String, Object?> w) async {
    final courseId = wireText(w['course_id']);
    if (!await _exists(db, 'courses', courseId)) return;
    await db
        .into(db.students)
        .insertOnConflictUpdate(
          StudentsCompanion.insert(
            id: w['id']! as String,
            courseId: courseId,
            firstName: wireText(w['first_name']),
            lastName: Value(wireText(w['last_name'])),
            studentNumber: Value(wireText(w['student_number'])),
            email: Value(wireText(w['email'])),
            notes: Value(wireText(w['notes'])),
            archived: Value(wireBool(w['archived'])),
          ),
        );
  }

  @override
  Future<void> delete(String id) =>
      (db.delete(db.students)..where((t) => t.id.equals(id))).go();

  @override
  Future<List<String>> ids() async =>
      (await db.select(db.students).get()).map((r) => r.id).toList();

  @override
  Future<void> clear() => db.delete(db.students).go();
}

final class AssignmentsSync extends _RubricSyncTable {
  new(super.db, super.owner);

  @override
  String get name => 'assignments';

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final r = await (db.select(
      db.assignments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    return withOwner({
      'id': r.id,
      'course_id': r.courseId,
      'title': r.title,
      'description': r.description,
      'rubric_document': r.rubricDocument,
      'source_rubric_id': r.sourceRubricId,
      'due_on': r.dueDate?.millisecondsSinceEpoch,
      'points_possible': r.pointsPossible,
      'closed': r.closed,
      'created_on': r.createdAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> write(Map<String, Object?> w) async {
    final courseId = wireText(w['course_id']);
    if (!await _exists(db, 'courses', courseId)) return;
    await db
        .into(db.assignments)
        .insertOnConflictUpdate(
          AssignmentsCompanion.insert(
            id: w['id']! as String,
            courseId: courseId,
            title: wireText(w['title']),
            description: Value(wireText(w['description'])),
            rubricDocument: wireText(w['rubric_document']),
            sourceRubricId: Value(w['source_rubric_id'] as String?),
            dueDate: Value(wireDate(w['due_on'])),
            pointsPossible: Value(
              (w['points_possible'] as num?)?.toDouble() ?? 100,
            ),
            closed: Value(wireBool(w['closed'])),
            createdAt: wireDate(w['created_on']) ?? DateTime.now(),
          ),
        );
  }

  @override
  Future<void> delete(String id) =>
      (db.delete(db.assignments)..where((t) => t.id.equals(id))).go();

  @override
  Future<List<String>> ids() async =>
      (await db.select(db.assignments).get()).map((r) => r.id).toList();

  @override
  Future<void> clear() => db.delete(db.assignments).go();
}

final class EvaluationsSync extends _RubricSyncTable {
  new(super.db, super.owner);

  @override
  String get name => 'evaluations';

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final r = await (db.select(
      db.evaluations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    return withOwner({
      'id': r.id,
      'assignment_id': r.assignmentId,
      'student_id': r.studentId,
      'status': r.status,
      'document': r.document,
      'updated_on': r.updatedAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> write(Map<String, Object?> w) async {
    final assignmentId = wireText(w['assignment_id']);
    final studentId = wireText(w['student_id']);
    if (!await _exists(db, 'assignments', assignmentId) ||
        !await _exists(db, 'students', studentId)) {
      return;
    }
    await db
        .into(db.evaluations)
        .insertOnConflictUpdate(
          EvaluationsCompanion.insert(
            id: w['id']! as String,
            assignmentId: assignmentId,
            studentId: studentId,
            status: wireText(w['status']),
            document: wireText(w['document']),
            updatedAt: wireDate(w['updated_on']) ?? DateTime.now(),
          ),
        );
  }

  @override
  Future<void> delete(String id) =>
      (db.delete(db.evaluations)..where((t) => t.id.equals(id))).go();

  @override
  Future<List<String>> ids() async =>
      (await db.select(db.evaluations).get()).map((r) => r.id).toList();

  @override
  Future<void> clear() => db.delete(db.evaluations).go();
}

/// All adapters, in [syncTables] order.
List<DriftSyncTable> rubricSyncTables(
  AppDatabase db,
  String? Function() owner,
) => [
  RubricsSync(db, owner),
  CommentSnippetsSync(db, owner),
  CoursesSync(db, owner),
  StudentsSync(db, owner),
  AssignmentsSync(db, owner),
  EvaluationsSync(db, owner),
];
