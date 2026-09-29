import 'package:collection/collection.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';

/// Which greeting the time of day calls for.
enum DayPeriod { morning, afternoon, evening }

DayPeriod dayPeriodOf(DateTime time) => switch (time.hour) {
  < 12 => DayPeriod.morning,
  < 17 => DayPeriod.afternoon,
  _ => DayPeriod.evening,
};

/// Monday 00:00 of the week containing [time].
DateTime startOfWeek(DateTime time) =>
    DateTime(time.year, time.month, time.day - (time.weekday - 1));

const Set<EvaluationStatus> _resolved = {
  EvaluationStatus.complete,
  EvaluationStatus.excused,
  EvaluationStatus.missing,
};

/// Where one assignment stands: how many of the class's papers are resolved.
class AssignmentProgress {
  const new({
    required this.assignment,
    required this.course,
    required this.total,
    required this.done,
  });

  final Assignment assignment;
  final Course course;

  /// Active students in the course.
  final int total;

  /// Papers that need nothing more: complete, excused or marked missing.
  final int done;

  int get remaining => total - done;
  double get progress => total == 0 ? 0 : done / total;
}

/// Everything the Home tab shows, derived from the stores in one pass.
class HomeDashboard {
  const new({
    required this.toGrade,
    required this.comingUp,
    required this.courses,
    required this.studentCount,
    required this.gradedThisWeek,
    required this.recentRubrics,
  });

  /// Builds the dashboard as of [now].
  ///
  /// An assignment is "to grade" once it is due (or undated) or once grading
  /// has started, and while any active student's paper is unresolved. Overdue
  /// work comes first, oldest due date first, undated last. Assignments not
  /// yet due and untouched are "coming up" when due within [lookAhead].
  /// Closed assignments and courses not in [courses] (archived) are ignored.
  factory compute({
    required DateTime now,
    required List<Course> courses,
    required Map<String, List<Student>> studentsByCourse,
    required List<Assignment> assignments,
    required Map<String, List<Evaluation>> evaluationsByCourse,
    required List<Rubric> rubrics,
  }) {
    final endOfToday = DateTime(now.year, now.month, now.day + 1);
    final weekStart = startOfWeek(now);

    final toGrade = <AssignmentProgress>[];
    final comingUp = <AssignmentProgress>[];
    var gradedThisWeek = 0;

    for (final course in courses) {
      final active = {
        for (final s in studentsByCourse[course.id] ?? const <Student>[])
          if (!s.archived) s.id,
      };
      final evaluations = (evaluationsByCourse[course.id] ?? const [])
          .where((e) => active.contains(e.studentId))
          .toList();
      gradedThisWeek += evaluations
          .where(
            (e) =>
                e.status == EvaluationStatus.complete &&
                !e.updatedAt.isBefore(weekStart),
          )
          .length;

      final byAssignment = evaluations.groupListsBy((e) => e.assignmentId);
      for (final assignment in assignments) {
        if (assignment.courseId != course.id || assignment.closed) continue;
        final evals = byAssignment[assignment.id] ?? const <Evaluation>[];
        final progress = AssignmentProgress(
          assignment: assignment,
          course: course,
          total: active.length,
          done: evals.where((e) => _resolved.contains(e.status)).length,
        );
        final started = evals.any(
          (e) => e.status != EvaluationStatus.notStarted,
        );
        final due = assignment.dueDate;
        final isDue = due == null || due.isBefore(endOfToday);

        if ((isDue || started) && progress.remaining > 0) {
          toGrade.add(progress);
        } else if (due != null &&
            !started &&
            due.isBefore(now.add(lookAhead))) {
          comingUp.add(progress);
        }
      }
    }

    int byDue(AssignmentProgress a, AssignmentProgress b) {
      final da = a.assignment.dueDate;
      final db = b.assignment.dueDate;
      if (da == null && db == null) {
        return a.assignment.title.compareTo(b.assignment.title);
      }
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    }

    return HomeDashboard(
      toGrade: toGrade..sort(byDue),
      comingUp: comingUp..sort(byDue),
      courses: courses,
      studentCount: courses.fold(
        0,
        (sum, c) =>
            sum +
            (studentsByCourse[c.id] ?? const [])
                .where((s) => !s.archived)
                .length,
      ),
      gradedThisWeek: gradedThisWeek,
      recentRubrics: rubrics
          .where((r) => !r.archived && !r.isTemplate)
          .sorted((a, b) => b.updatedAt.compareTo(a.updatedAt))
          .take(recentRubricCount)
          .toList(),
    );
  }

  /// How far ahead "Coming up" looks.
  static const lookAhead = Duration(days: 14);
  static const recentRubricCount = 3;

  final List<AssignmentProgress> toGrade;
  final List<AssignmentProgress> comingUp;
  final List<Course> courses;
  final int studentCount;
  final int gradedThisWeek;
  final List<Rubric> recentRubrics;

  /// A brand-new teacher: nothing to show but a way in.
  bool get isEmpty => courses.isEmpty && recentRubrics.isEmpty;
}
