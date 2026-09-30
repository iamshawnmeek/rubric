import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/comment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/data/sync_writer.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/sync/sync_service.dart';

/// Overridden in main() and in tests (with an in-memory database).
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Where every repository write goes. Local-only by default (tests, and before
/// sync is set up); main() overrides it with the app's [SyncService].
final syncWriterProvider = Provider<SyncWriter>(
  (ref) => LocalWriter(ref.watch(databaseProvider)),
);

/// The app's sync service, or null where sync is not set up (tests).
final syncServiceProvider = Provider<SyncService?>((ref) => null);

/// Sign-in state and sync progress, for the UI.
final syncStateProvider = StreamProvider<SyncState>((ref) {
  final sync = ref.watch(syncServiceProvider);
  if (sync == null) return Stream.value(SyncState.signedOut);
  return (() async* {
    yield sync.state;
    yield* sync.states;
  })();
});

final Provider<RubricRepository> rubricRepositoryProvider = Provider(
  (ref) => RubricRepository(
    ref.watch(databaseProvider),
    ref.watch(syncWriterProvider),
  ),
);
final Provider<CourseRepository> courseRepositoryProvider = Provider(
  (ref) => CourseRepository(
    ref.watch(databaseProvider),
    ref.watch(syncWriterProvider),
  ),
);
final Provider<AssignmentRepository> assignmentRepositoryProvider = Provider(
  (ref) => AssignmentRepository(
    ref.watch(databaseProvider),
    ref.watch(syncWriterProvider),
  ),
);
final Provider<CommentRepository> commentRepositoryProvider = Provider(
  (ref) => CommentRepository(
    ref.watch(databaseProvider),
    ref.watch(syncWriterProvider),
  ),
);

// ---- Shared read models. Features add their own next to their screens; these
// ---- are the ones more than one feature needs.

final rubricsProvider = StreamProvider<List<Rubric>>(
  (ref) => ref.watch(rubricRepositoryProvider).watchAll(),
);

final templatesProvider = StreamProvider<List<Rubric>>(
  (ref) => ref.watch(rubricRepositoryProvider).watchAll(templates: true),
);

final StreamProviderFamily<Rubric?, String> rubricProvider =
    StreamProvider.family<Rubric?, String>(
      (ref, id) => ref.watch(rubricRepositoryProvider).watch(id),
    );

final coursesProvider = StreamProvider<List<Course>>(
  (ref) => ref.watch(courseRepositoryProvider).watchCourses(),
);

final StreamProviderFamily<Course?, String> courseProvider =
    StreamProvider.family<Course?, String>(
      (ref, id) => ref.watch(courseRepositoryProvider).watchCourse(id),
    );

final StreamProviderFamily<List<Student>, String> studentsProvider =
    StreamProvider.family<List<Student>, String>(
      (ref, courseId) =>
          ref.watch(courseRepositoryProvider).watchStudents(courseId),
    );

final StreamProviderFamily<Student?, String> studentProvider =
    StreamProvider.family<Student?, String>(
      (ref, id) => ref.watch(courseRepositoryProvider).watchStudent(id),
    );

final studentCountsProvider = StreamProvider<Map<String, int>>(
  (ref) => ref.watch(courseRepositoryProvider).watchStudentCounts(),
);

final StreamProviderFamily<List<Assignment>, String> assignmentsProvider =
    StreamProvider.family<List<Assignment>, String>(
      (ref, courseId) =>
          ref.watch(assignmentRepositoryProvider).watchForCourse(courseId),
    );

final allAssignmentsProvider = StreamProvider<List<Assignment>>(
  (ref) => ref.watch(assignmentRepositoryProvider).watchAll(),
);

final StreamProviderFamily<Assignment?, String> assignmentProvider =
    StreamProvider.family<Assignment?, String>(
      (ref, id) => ref.watch(assignmentRepositoryProvider).watch(id),
    );

final StreamProviderFamily<List<Evaluation>, String> evaluationsProvider =
    StreamProvider.family<List<Evaluation>, String>(
      (ref, assignmentId) => ref
          .watch(assignmentRepositoryProvider)
          .watchEvaluations(assignmentId),
    );

final StreamProviderFamily<List<Evaluation>, String> courseEvaluationsProvider =
    StreamProvider.family<List<Evaluation>, String>(
      (ref, courseId) => ref
          .watch(assignmentRepositoryProvider)
          .watchEvaluationsForCourse(courseId),
    );

final StreamProviderFamily<List<Evaluation>, String>
studentEvaluationsProvider = StreamProvider.family<List<Evaluation>, String>(
  (ref, studentId) => ref
      .watch(assignmentRepositoryProvider)
      .watchEvaluationsForStudent(studentId),
);

final commentSnippetsProvider = StreamProvider<List<CommentSnippet>>(
  (ref) => ref.watch(commentRepositoryProvider).watchAll(),
);
