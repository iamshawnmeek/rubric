import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/sync_writer.dart';
import 'package:rubric/domain/rubric.dart';

class RubricRepository {
  /// [writer] defaults to local-only writes; the app passes its sync
  /// service so writes are also queued for the server.
  new(this._db, [SyncWriter? writer]) : _writer = writer ?? LocalWriter(_db);

  final AppDatabase _db;
  final SyncWriter _writer;

  static Map<String, Object?> toWire(Rubric r) => {
    'id': r.id,
    'title': r.title,
    'subject': r.subject,
    'is_template': r.isTemplate,
    'archived': r.archived,
    'document': jsonEncode(r.toJson()),
    'created_on': r.createdAt.millisecondsSinceEpoch,
  };

  static Rubric _fromRow(RubricRow row) =>
      Rubric.fromJson(jsonDecode(row.document) as Map<String, dynamic>);

  /// Library rubrics, most recently edited first.
  Stream<List<Rubric>> watchAll({
    bool templates = false,
    bool archived = false,
  }) {
    final query = _db.select(_db.rubrics)
      ..where(
        (r) => r.isTemplate.equals(templates) & r.archived.equals(archived),
      )
      ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)]);
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  Stream<Rubric?> watch(String id) =>
      (_db.select(_db.rubrics)..where((r) => r.id.equals(id)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : _fromRow(row));

  Future<Rubric?> get(String id) async {
    final row = await (_db.select(
      _db.rubrics,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<List<Rubric>> all() async =>
      (await _db.select(_db.rubrics).get()).map(_fromRow).toList();

  /// Inserts or replaces [rubric], stamping [Rubric.updatedAt].
  Future<Rubric> save(Rubric rubric, {DateTime? now}) async {
    final stamped = rubric.copyWith(updatedAt: now ?? DateTime.now());
    await _writer.upsert('rubrics', toWire(stamped));
    return stamped;
  }

  Future<void> delete(String id) => _writer.delete('rubrics', id);

  Future<void> setArchived(String id, {required bool archived}) async {
    final rubric = await get(id);
    if (rubric != null) {
      await save(rubric.copyWith(archived: archived));
    }
  }
}
