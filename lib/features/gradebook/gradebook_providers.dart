import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:rubric/data/providers.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/features/gradebook/gradebook_model.dart';

/// A course's gradebook over its active roster, rebuilt whenever a student,
/// assignment or grade in it changes.
final ProviderFamily<AsyncValue<Gradebook>, String> gradebookProvider =
    Provider.family<AsyncValue<Gradebook>, String>(_build);

/// The course gradebook as seen from one student's profile: the same grid,
/// plus that student's row even when they have been archived off the roster.
final ProviderFamily<AsyncValue<Gradebook>, (String, String)>
studentGradebookProvider =
    Provider.family<AsyncValue<Gradebook>, (String, String)>((ref, key) {
      final (courseId, studentId) = key;
      final student = ref.watch(studentProvider(studentId));
      if (student case AsyncError(:final error, :final stackTrace)) {
        return AsyncError(error, stackTrace);
      }
      if (!student.hasValue) return const AsyncLoading();
      return _build(ref, courseId, include: student.requireValue);
    });

AsyncValue<Gradebook> _build(Ref ref, String courseId, {Student? include}) {
  final students = ref.watch(studentsProvider(courseId));
  final assignments = ref.watch(assignmentsProvider(courseId));
  final evaluations = ref.watch(courseEvaluationsProvider(courseId));
  for (final v in [students, assignments, evaluations]) {
    if (v case AsyncError(:final error, :final stackTrace)) {
      return AsyncError(error, stackTrace);
    }
  }
  if (!students.hasValue || !assignments.hasValue || !evaluations.hasValue) {
    return const AsyncLoading();
  }
  final roster = students.requireValue;
  return AsyncData(
    Gradebook.build(
      students: [
        ...roster,
        if (include != null && !roster.any((s) => s.id == include.id)) include,
      ],
      assignments: assignments.requireValue,
      evaluations: evaluations.requireValue,
    ),
  );
}
