import 'package:rubric/data/database.dart';

/// Deletes every row in every table, in one transaction: either the device is
/// wiped clean or nothing changes.
///
/// Walks [AppDatabase.allTables] rather than naming tables, so a table added to
/// the schema later is erased too instead of silently surviving a wipe.
Future<void> eraseAllData(AppDatabase db) => db.transaction(() async {
  // Children before parents is not guaranteed for future tables; deferring the
  // checks to commit makes the order irrelevant.
  await db.customStatement('PRAGMA defer_foreign_keys = ON');
  for (final table in db.allTables.toList().reversed) {
    await db.delete(table).go();
  }
});
