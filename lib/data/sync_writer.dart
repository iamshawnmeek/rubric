import 'package:rubric/data/database.dart';
import 'package:rubric/sync/sync_tables.dart';
import 'package:zonai_sync_drift/zonai_sync_drift.dart';

/// Where repositories send every write.
///
/// Signed out, a write goes straight to the local database. Signed in, it goes
/// through the sync engine, which writes the same local row AND queues it for
/// the server in one transaction. Repositories never know which.
abstract interface class SyncWriter {
  /// Inserts or replaces a row, given in the server's wire format.
  Future<void> upsert(String table, Map<String, Object?> wire);

  Future<void> delete(String table, String id);
}

/// Writes locally only, through the same table adapters sync uses, so the
/// wire <-> row mapping is identical whether or not anyone is signed in.
final class LocalWriter implements SyncWriter {
  new(AppDatabase db)
    : _tables = {for (final t in rubricSyncTables(db, () => null)) t.name: t};

  final Map<String, DriftSyncTable> _tables;

  DriftSyncTable _t(String name) =>
      _tables[name] ?? (throw ArgumentError('Unknown table $name'));

  @override
  Future<void> upsert(String table, Map<String, Object?> wire) =>
      _t(table).write(wire);

  @override
  Future<void> delete(String table, String id) => _t(table).delete(id);
}
