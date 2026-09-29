import 'package:drift/drift.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/domain/evaluation.dart';

class CommentRepository {
  new(this._db);

  final AppDatabase _db;

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

  Future<void> save(CommentSnippet s) => _db
      .into(_db.commentSnippets)
      .insertOnConflictUpdate(
        CommentSnippetsCompanion.insert(
          id: s.id,
          body: s.text,
          category: Value(s.category),
          useCount: Value(s.useCount),
        ),
      );

  Future<void> delete(String id) =>
      (_db.delete(_db.commentSnippets)..where((c) => c.id.equals(id))).go();

  Future<void> recordUse(String id) => _db.customUpdate(
    'UPDATE comment_snippets SET use_count = use_count + 1 WHERE id = ?',
    variables: [Variable.withString(id)],
    updates: {_db.commentSnippets},
  );
}
