import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// Structured documents (a rubric's groups/objectives/levels, an evaluation's
// scores) are stored as JSON text. They are always read and written whole, and
// the domain layer owns their shape — splitting them into tables would buy
// nothing but joins. Everything that is queried, filtered or sorted on is a
// real column.

@DataClassName('RubricRow')
class Rubrics extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get subject => text().withDefault(const Constant(''))();
  BoolColumn get isTemplate => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get document => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CourseRow')
class Courses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get section => text().withDefault(const Constant(''))();
  TextColumn get term => text().withDefault(const Constant(''))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('StudentRow')
class Students extends Table {
  TextColumn get id => text()();
  TextColumn get courseId =>
      text().references(Courses, #id, onDelete: KeyAction.cascade)();
  TextColumn get firstName => text()();
  TextColumn get lastName => text().withDefault(const Constant(''))();
  TextColumn get studentNumber => text().withDefault(const Constant(''))();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AssignmentRow')
class Assignments extends Table {
  TextColumn get id => text()();
  TextColumn get courseId =>
      text().references(Courses, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get rubricDocument => text()();
  TextColumn get sourceRubricId => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  RealColumn get pointsPossible => real().withDefault(const Constant(100))();
  BoolColumn get closed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('EvaluationRow')
class Evaluations extends Table {
  TextColumn get id => text()();
  TextColumn get assignmentId =>
      text().references(Assignments, #id, onDelete: KeyAction.cascade)();
  TextColumn get studentId =>
      text().references(Students, #id, onDelete: KeyAction.cascade)();
  TextColumn get status => text()();
  TextColumn get document => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {assignmentId, studentId},
  ];
}

@DataClassName('CommentSnippetRow')
class CommentSnippets extends Table {
  TextColumn get id => text()();
  TextColumn get body => text()();
  TextColumn get category => text().withDefault(const Constant(''))();
  IntColumn get useCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Rubrics,
    Courses,
    Students,
    Assignments,
    Evaluations,
    CommentSnippets,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Tests pass `NativeDatabase.memory()` from package:drift/native.dart.
  new([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _open() => driftDatabase(name: 'rubric');
}
