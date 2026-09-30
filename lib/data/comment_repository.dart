import 'package:drift/drift.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/sync_writer.dart';
import 'package:rubric/domain/evaluation.dart';

class CommentRepository {
  /// [writer] defaults to local-only writes; the app passes its sync
  /// service so writes are also queued for the server.
  new(this._db, [SyncWriter? writer]) : _writer = writer ?? LocalWriter(_db);

  final AppDatabase _db;
  final SyncWriter _writer;

  static Map<String, Object?> toWire(CommentSnippet s) => {
    'id': s.id,
    'body': s.text,
    'category': s.category,
    'use_count': s.useCount,
  };

  static CommentSnippet _snippet(CommentSnippetRow r) => CommentSnippet(
    id: r.id,
    text: r.body,
    category: r.category,
    useCount: r.useCount,
  );

  /// Most-used first, so the comments a teacher reaches for are on top.
  Stream<List<CommentSnippet>> watchAll() {
    final q = _db.select(_db.commentSnippets)
      ..orderBy([
        (c) => OrderingTerm.desc(c.useCount),
        (c) => OrderingTerm.asc(c.body),
      ]);
    return q.watch().map((rows) => rows.map(_snippet).toList());
  }

  Future<List<CommentSnippet>> all() async =>
      (await _db.select(_db.commentSnippets).get()).map(_snippet).toList();

  Future<void> save(CommentSnippet s) =>
      _writer.upsert('comment_snippets', toWire(s));

  Future<void> delete(String id) => _writer.delete('comment_snippets', id);

  /// Bumps the use count (through sync, so ordering follows the teacher
  /// across devices).
  Future<void> recordUse(String id) async {
    final row = await (_db.select(
      _db.commentSnippets,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await save(_snippet(row).copyWith(useCount: row.useCount + 1));
  }
}
