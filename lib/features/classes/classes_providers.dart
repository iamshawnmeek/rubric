import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;
import 'package:rubric/data/providers.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';

/// Archived courses, by name. The active list is the shared [coursesProvider].
final archivedCoursesProvider = StreamProvider<List<Course>>(
  (ref) => ref.watch(courseRepositoryProvider).watchCourses(archived: true),
);

/// Archived students of a course, sorted like the active roster.
final StreamProviderFamily<List<Student>, String> archivedStudentsProvider =
    StreamProvider.family<List<Student>, String>(
      (ref, courseId) => ref
          .watch(courseRepositoryProvider)
          .watchStudents(courseId, archived: true),
    );

/// A graded x/y tally for one assignment.
typedef GradingProgress = ({int graded, int total});

/// How many of [studentIds] have a finished mark on [assignmentId]: complete,
/// excused and missing all count as decided; not-started and in-progress do
/// not. Evaluations for students outside [studentIds] (archived, removed) are
/// ignored so the numerator never exceeds the roster.
GradingProgress gradingProgress(
  String assignmentId,
  Iterable<Evaluation> evaluations,
  Set<String> studentIds,
) {
  final graded = <String>{
    for (final e in evaluations)
      if (e.assignmentId == assignmentId &&
          studentIds.contains(e.studentId) &&
          switch (e.status) {
            EvaluationStatus.complete ||
            EvaluationStatus.excused ||
            EvaluationStatus.missing => true,
            EvaluationStatus.notStarted || EvaluationStatus.inProgress => false,
          })
        e.studentId,
  };
  return (graded: graded.length, total: studentIds.length);
}

/// Whether any work in the course has been marked — the bar for making a
/// teacher type the class name before deleting it.
bool hasAnyGrades(Iterable<Evaluation> evaluations) => evaluations.any(
  (e) => e.status != EvaluationStatus.notStarted || e.scores.isNotEmpty,
);
