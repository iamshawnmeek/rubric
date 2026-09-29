import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:rubric/data/database.dart';

/// A fresh in-memory database. Close it in tearDown.
AppDatabase testDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}
