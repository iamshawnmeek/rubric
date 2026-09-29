import 'package:collection/collection.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';

/// The computed outcome of grading one [Evaluation] against a [Rubric].
class ScoreResult {
  const new({
    required this.objectivePercents,
    required this.groupPercents,
    required this.scoredCount,
    required this.totalCount,
    this.rawPercent,
    this.percent,
    this.letter,
  });

  /// 0–100 per objective id, null where not yet scored.
  final Map<String, double?> objectivePercents;

  /// 0–100 per group id, null where no objective in it is scored.
  final Map<String, double?> groupPercents;

  /// Weighted result before penalty/override; null when nothing is scored or
  /// the student is excused.
  final double? rawPercent;

  /// The grade of record: after penalty and override.
  final double? percent;
  final String? letter;
  final int scoredCount;
  final int totalCount;

  bool get isComplete => totalCount > 0 && scoredCount == totalCount;
  double get progress => totalCount == 0 ? 0 : scoredCount / totalCount;
}

abstract final class Scoring {
  /// 0–100 for a single objective score, or null if it cannot be read against
  /// [rubric] (e.g. a level that no longer exists).
  static double? objectivePercent(Rubric rubric, ObjectiveScore? score) {
    switch (score) {
      case null:
        return null;
      case PercentScore(:final value):
        return value.clamp(0, 100).toDouble();
      case LevelScore(:final levelId):
        final level = rubric.levelById(levelId);
        final max = rubric.maxLevelPoints;
        if (level == null || max <= 0) return null;
        return level.points / max * 100;
    }
  }

  /// Grades [evaluation] against [rubric].
  ///
  /// Group percent is the mean of its SCORED objectives; the overall percent
  /// is the weight-averaged group percents over the groups that have any
  /// score, so a partially-graded paper shows a meaningful running grade.
  /// A [EvaluationStatus.missing] paper with no scores counts as 0.
  static ScoreResult score(Rubric rubric, Evaluation evaluation) {
    final objectivePercents = <String, double?>{};
    final groupPercents = <String, double?>{};
    var scored = 0;
    var weightedSum = 0.0;
    var weightTotal = 0;

    for (final group in rubric.groups) {
      final values = <double>[];
      for (final objective in group.objectives) {
        final p = objectivePercent(rubric, evaluation.scores[objective.id]);
        objectivePercents[objective.id] = p;
        if (p != null) {
          values.add(p);
          scored++;
        }
      }
      final groupPercent = values.isEmpty ? null : values.average;
      groupPercents[group.id] = groupPercent;
      if (groupPercent != null) {
        weightedSum += groupPercent * group.weight;
        weightTotal += group.weight;
      }
    }

    final total = rubric.objectives.length;
    var raw = weightTotal == 0 ? null : weightedSum / weightTotal;
    if (evaluation.status == EvaluationStatus.missing && scored == 0) raw = 0;
    if (evaluation.status == EvaluationStatus.excused) raw = null;

    var finalPercent = raw;
    if (finalPercent != null && evaluation.penaltyPercent > 0) {
      finalPercent = (finalPercent - evaluation.penaltyPercent).clamp(0, 100);
    }
    if (evaluation.overridePercent != null &&
        evaluation.status != EvaluationStatus.excused) {
      finalPercent = evaluation.overridePercent!.clamp(0, 100).toDouble();
    }

    return ScoreResult(
      objectivePercents: objectivePercents,
      groupPercents: groupPercents,
      rawPercent: raw,
      percent: finalPercent,
      letter: finalPercent == null
          ? null
          : rubric.scale.letterFor(finalPercent),
      scoredCount: scored,
      totalCount: total,
    );
  }

  /// The status an evaluation should carry after its scores change, unless
  /// the teacher has explicitly marked it excused or missing.
  static EvaluationStatus derivedStatus(Rubric rubric, Evaluation evaluation) {
    if (evaluation.status == EvaluationStatus.excused) {
      return EvaluationStatus.excused;
    }
    final ids = rubric.objectives.map((o) => o.id).toSet();
    final scored = evaluation.scores.keys.where(ids.contains).length;
    if (scored == 0) {
      return evaluation.status == EvaluationStatus.missing
          ? EvaluationStatus.missing
          : EvaluationStatus.notStarted;
    }
    return scored == ids.length
        ? EvaluationStatus.complete
        : EvaluationStatus.inProgress;
  }

  /// Points earned out of [pointsPossible] for exports.
  static double? points(ScoreResult result, double pointsPossible) =>
      result.percent == null ? null : result.percent! / 100 * pointsPossible;
}
