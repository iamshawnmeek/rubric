import 'package:collection/collection.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/domain/stats.dart';

/// The pure rules behind the grading screen. Every edit the teacher makes is
/// one of these functions applied to an [Evaluation]; the controller only
/// sequences them, saves, and keeps the undo stack.
abstract final class GradingLogic {
  /// The quick-pick percentages offered on simple rubrics.
  static const quickPicks = <double>[100, 90, 80, 70, 60, 50, 0];

  /// Sets (or clears, when [score] is null) one objective and re-derives the
  /// status: scoring a missing paper means it was handed in after all.
  static Evaluation setScore(
    Rubric rubric,
    Evaluation e,
    String objectiveId,
    ObjectiveScore? score, {
    DateTime? now,
  }) =>
      _derive(rubric, e.withScore(objectiveId, score).copyWith(updatedAt: now));

  /// Tapping the selected level again clears it; any other level selects it.
  static Evaluation toggleLevel(
    Rubric rubric,
    Evaluation e,
    String objectiveId,
    String levelId, {
    DateTime? now,
  }) {
    final current = e.scores[objectiveId];
    final next = current == LevelScore(levelId) ? null : LevelScore(levelId);
    return setScore(rubric, e, objectiveId, next, now: now);
  }

  /// Marks the work missing (counts as zero until scored) or reverts to the
  /// status its scores imply. Missing and excused are mutually exclusive.
  static Evaluation setMissing(
    Rubric rubric,
    Evaluation e, {
    required bool missing,
    DateTime? now,
  }) => missing
      ? e.copyWith(status: EvaluationStatus.missing, updatedAt: now)
      : _derive(
          rubric,
          e.copyWith(status: EvaluationStatus.notStarted, updatedAt: now),
        );

  /// Excuses the student (no grade, not counted in averages) or reverts to
  /// the status its scores imply.
  static Evaluation setExcused(
    Rubric rubric,
    Evaluation e, {
    required bool excused,
    DateTime? now,
  }) => excused
      ? e.copyWith(status: EvaluationStatus.excused, updatedAt: now)
      : _derive(
          rubric,
          e.copyWith(status: EvaluationStatus.notStarted, updatedAt: now),
        );

  /// Turning late on applies [defaultPenalty] unless a penalty is already
  /// set; turning it off removes the penalty with it.
  static Evaluation setLate(
    Evaluation e, {
    required bool late,
    required double defaultPenalty,
    DateTime? now,
  }) => e.copyWith(
    late: late,
    penaltyPercent: late
        ? (e.penaltyPercent > 0 ? e.penaltyPercent : _pct(defaultPenalty))
        : 0,
    updatedAt: now,
  );

  /// Percentage points deducted, clamped to 0–100.
  static Evaluation setPenalty(Evaluation e, double penalty, {DateTime? now}) =>
      e.copyWith(penaltyPercent: _pct(penalty), updatedAt: now);

  /// Replaces the computed grade with [percent] (clamped), or clears the
  /// override and its reason when [percent] is null.
  static Evaluation setOverride(
    Evaluation e,
    double? percent, {
    String reason = '',
    DateTime? now,
  }) => percent == null
      ? e.copyWith(clearOverride: true, updatedAt: now)
      : e.copyWith(
          overridePercent: _pct(percent),
          overrideReason: reason.trim(),
          updatedAt: now,
        );

  static Evaluation setComment(Evaluation e, String comment, {DateTime? now}) =>
      e.copyWith(comment: comment, updatedAt: now);

  static Evaluation setObjectiveComment(
    Evaluation e,
    String objectiveId,
    String comment, {
    DateTime? now,
  }) {
    final next = Map<String, String>.of(e.objectiveComments);
    if (comment.trim().isEmpty) {
      next.remove(objectiveId);
    } else {
      next[objectiveId] = comment;
    }
    return e.copyWith(objectiveComments: next, updatedAt: now);
  }

  /// Appends [snippet] to [comment] as a new sentence/paragraph.
  static String insertSnippet(String comment, String snippet) {
    final base = comment.trimRight();
    if (base.isEmpty) return snippet.trim();
    return '$base ${snippet.trim()}';
  }

  /// Parses a typed percentage ("87", "87.5", "87%"); null when unreadable.
  static double? parsePercent(String input) {
    final cleaned = input.replaceAll('%', '').trim();
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN) return null;
    return _pct(value);
  }

  /// Whether the teacher is done with this student: every objective scored,
  /// or a decision recorded that stands in for scores.
  static bool isGraded(Rubric rubric, Evaluation? e) {
    if (e == null) return false;
    if (e.status == EvaluationStatus.excused ||
        e.status == EvaluationStatus.missing) {
      return true;
    }
    return switch (Scoring.derivedStatus(rubric, e)) {
      EvaluationStatus.complete ||
      EvaluationStatus.excused ||
      EvaluationStatus.missing => true,
      EvaluationStatus.notStarted ||
      EvaluationStatus.inProgress => e.overridePercent != null,
    };
  }

  /// The first ungraded student AFTER [currentId] in roster order, wrapping
  /// round; the current student counts only if nobody else is ungraded.
  /// Null when everyone is graded.
  static String? nextUngraded(
    Rubric rubric,
    List<Student> ordered,
    Map<String, Evaluation> byStudent,
    String currentId,
  ) {
    if (ordered.isEmpty) return null;
    final start = ordered.indexWhere((s) => s.id == currentId);
    for (var step = 1; step <= ordered.length; step++) {
      final s = ordered[(start + step) % ordered.length];
      if (!isGraded(rubric, byStudent[s.id])) return s.id;
    }
    return null;
  }

  static bool allGraded(
    Rubric rubric,
    List<Student> ordered,
    Map<String, Evaluation> byStudent,
  ) =>
      ordered.isNotEmpty &&
      ordered.every((s) => isGraded(rubric, byStudent[s.id]));

  /// The neighbour of [currentId] in roster order; null at either end.
  static String? neighbour(
    List<Student> ordered,
    String currentId, {
    required bool forward,
  }) {
    final i = ordered.indexWhere((s) => s.id == currentId);
    if (i < 0) return ordered.firstOrNull?.id;
    final j = forward ? i + 1 : i - 1;
    return j < 0 || j >= ordered.length ? null : ordered[j].id;
  }

  /// Mean grade of record across the roster; excused and ungraded students
  /// are left out (via [AssignmentStats]).
  static double? classAverage(
    Rubric rubric,
    List<Student> ordered,
    Map<String, Evaluation> byStudent,
  ) => AssignmentStats.compute(rubric, [
    for (final s in ordered) ?byStudent[s.id],
  ]).overall.mean;

  static Evaluation _derive(Rubric rubric, Evaluation e) => e.copyWith(
    status: Scoring.derivedStatus(rubric, e),
    updatedAt: e.updatedAt,
  );

  static double _pct(double v) => v.clamp(0, 100).toDouble();
}
