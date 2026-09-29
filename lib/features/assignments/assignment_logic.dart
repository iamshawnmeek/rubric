import 'package:collection/collection.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/scoring.dart';

/// A fresh `notStarted` evaluation for every student in [students] who does
/// not already have one on [assignment].
///
/// Used both when an assignment is created and lazily when the hub opens, so
/// students added to the course later still get a row.
List<Evaluation> missingEvaluations(
  Assignment assignment,
  Iterable<Student> students,
  Iterable<Evaluation> existing, {
  DateTime? now,
}) {
  final have = existing.map((e) => e.studentId).toSet();
  return [
    for (final s in students)
      if (!have.contains(s.id))
        Evaluation.start(
          assignmentId: assignment.id,
          studentId: s.id,
          now: now,
        ),
  ];
}

/// [evaluation] carried onto [rubric] after a re-snapshot: scores and
/// objective comments on objectives that still exist are kept (a level score
/// only if its level still exists), everything else is dropped, and the
/// status is re-derived. Excused and missing marks are the teacher's and stay.
Evaluation reconcileEvaluation(
  Rubric rubric,
  Evaluation evaluation, {
  DateTime? now,
}) {
  final ids = rubric.objectives.map((o) => o.id).toSet();
  bool keep(String id, ObjectiveScore score) =>
      ids.contains(id) &&
      switch (score) {
        PercentScore() => rubric.mode == GradingMode.simple,
        LevelScore(:final levelId) =>
          rubric.mode == GradingMode.detailed &&
              rubric.levelById(levelId) != null,
      };

  final next = evaluation.copyWith(
    scores: {
      for (final e in evaluation.scores.entries)
        if (keep(e.key, e.value)) e.key: e.value,
    },
    objectiveComments: {
      for (final e in evaluation.objectiveComments.entries)
        if (ids.contains(e.key)) e.key: e.value,
    },
    updatedAt: now,
  );
  return next.copyWith(
    status: Scoring.derivedStatus(rubric, next),
    updatedAt: now,
  );
}

/// Only rubrics without [Rubric.issues] can be graded against.
bool canAttach(Rubric rubric) => rubric.isReady;

/// The rubric as it is frozen into an assignment.
Rubric snapshotOf(Rubric rubric) =>
    rubric.isTemplate ? rubric.copyWith(isTemplate: false) : rubric;

/// Library rubrics matching [query] (title or subject, case-insensitive),
/// ready ones first, each group keeping its incoming order.
List<Rubric> filterRubrics(Iterable<Rubric> rubrics, String query) {
  final q = query.trim().toLowerCase();
  final matches = rubrics.where(
    (r) =>
        q.isEmpty ||
        r.title.toLowerCase().contains(q) ||
        r.subject.toLowerCase().contains(q),
  );
  return [...matches.where((r) => r.isReady), ...matches.whereNot(canAttach)];
}

/// One student's line on the assignment hub.
class HubRow {
  const new({
    required this.student,
    required this.evaluation,
    required this.result,
  });

  final Student student;
  final Evaluation evaluation;
  final ScoreResult result;

  EvaluationStatus get status => evaluation.status;

  /// Still needs the teacher's attention in a grading pass.
  bool get needsGrading =>
      status == EvaluationStatus.notStarted ||
      status == EvaluationStatus.inProgress;
}

enum HubSort { name, status, grade }

enum HubFilter { all, ungraded, complete, missing, excused }

/// Pairs each active student with their evaluation and computed grade.
/// Students without an evaluation yet are left out (they are being created).
List<HubRow> hubRows(
  Assignment assignment,
  Iterable<Student> students,
  Iterable<Evaluation> evaluations,
) {
  final byStudent = {for (final e in evaluations) e.studentId: e};
  return [
    for (final s in students)
      if (byStudent[s.id] case final e?)
        HubRow(
          student: s,
          evaluation: e,
          result: Scoring.score(assignment.rubric, e),
        ),
  ];
}

const List<EvaluationStatus> _statusOrder = [
  EvaluationStatus.notStarted,
  EvaluationStatus.inProgress,
  EvaluationStatus.missing,
  EvaluationStatus.complete,
  EvaluationStatus.excused,
];

/// [rows] filtered, searched by name and sorted. Grade sorts highest first
/// with ungraded students last; ties always fall back to name order.
List<HubRow> arrangeRows(
  Iterable<HubRow> rows, {
  HubSort sort = HubSort.name,
  HubFilter filter = HubFilter.all,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  bool passes(HubRow r) => switch (filter) {
    HubFilter.all => true,
    HubFilter.ungraded => r.needsGrading,
    HubFilter.complete => r.status == EvaluationStatus.complete,
    HubFilter.missing => r.status == EvaluationStatus.missing,
    HubFilter.excused => r.status == EvaluationStatus.excused,
  };
  int byName(HubRow a, HubRow b) => compareStudents(a.student, b.student);
  int compare(HubRow a, HubRow b) {
    final primary = switch (sort) {
      HubSort.name => 0,
      HubSort.status =>
        _statusOrder
            .indexOf(a.status)
            .compareTo(_statusOrder.indexOf(b.status)),
      HubSort.grade => switch ((a.result.percent, b.result.percent)) {
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
        (final x?, final y?) => y.compareTo(x),
      },
    };
    return primary != 0 ? primary : byName(a, b);
  }

  return rows
      .where(passes)
      .where(
        (r) =>
            q.isEmpty ||
            r.student.displayName.toLowerCase().contains(q) ||
            r.student.sortName.toLowerCase().contains(q),
      )
      .sorted(compare);
}

/// The student "Start/Continue grading" jumps to: the first in name order
/// whose paper still needs grading, or null when everyone is done.
Student? firstUngraded(Iterable<HubRow> rows) =>
    arrangeRows(rows).firstWhereOrNull((r) => r.needsGrading)?.student;

/// How many of [rows] are dealt with (complete, missing or excused) — the
/// numerator of the hub's "graded x of y".
int gradedCount(Iterable<HubRow> rows) =>
    rows.where((r) => !r.needsGrading).length;

/// [evaluation] back to a blank, not-started paper (same id and student).
Evaluation resetEvaluation(Evaluation evaluation, {DateTime? now}) =>
    Evaluation(
      id: evaluation.id,
      assignmentId: evaluation.assignmentId,
      studentId: evaluation.studentId,
      updatedAt: now ?? DateTime.now(),
    );

/// [assignment] re-snapshotted onto the current [library] rubric, with every
/// evaluation carried across by [reconcileEvaluation].
(Assignment, List<Evaluation>) resnapshot(
  Assignment assignment,
  Rubric library,
  Iterable<Evaluation> evaluations, {
  DateTime? now,
}) {
  final rubric = snapshotOf(library);
  return (
    assignment.copyWith(rubric: rubric),
    [for (final e in evaluations) reconcileEvaluation(rubric, e, now: now)],
  );
}
