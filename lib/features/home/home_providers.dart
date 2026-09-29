import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/features/home/home_dashboard.dart';

/// The Home tab's notion of "now". Overridden in tests to pin the calendar.
final homeClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The Home dashboard, recomputed whenever any store it reads changes.
///
/// Loading until every source has a value; the first error wins.
final homeDashboardProvider = Provider<AsyncValue<HomeDashboard>>((ref) {
  final courses = ref.watch(coursesProvider);
  final assignments = ref.watch(allAssignmentsProvider);
  final rubrics = ref.watch(rubricsProvider);

  final students = <String, AsyncValue<List<Student>>>{};
  final evaluations = <String, AsyncValue<List<Evaluation>>>{};
  for (final course in courses.value ?? const <Course>[]) {
    students[course.id] = ref.watch(studentsProvider(course.id));
    evaluations[course.id] = ref.watch(courseEvaluationsProvider(course.id));
  }

  final sources = <AsyncValue<Object?>>[
    courses,
    assignments,
    rubrics,
    ...students.values,
    ...evaluations.values,
  ];
  for (final source in sources) {
    if (source case AsyncError(:final error, :final stackTrace)) {
      return AsyncError(error, stackTrace);
    }
  }
  if (sources.any((s) => !s.hasValue)) return const AsyncLoading();

  return AsyncData(
    HomeDashboard.compute(
      now: ref.watch(homeClockProvider)(),
      courses: courses.requireValue,
      studentsByCourse: students.map((k, v) => MapEntry(k, v.requireValue)),
      assignments: assignments.requireValue,
      evaluationsByCourse: evaluations.map(
        (k, v) => MapEntry(k, v.requireValue),
      ),
      rubrics: rubrics.requireValue,
    ),
  );
});
