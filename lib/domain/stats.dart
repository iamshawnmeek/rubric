import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/scoring.dart';

/// Summary statistics over a set of percentages.
class Summary {
  const new({
    required this.count,
    this.mean,
    this.median,
    this.min,
    this.max,
    this.stdDev,
  });

  factory of(Iterable<double> values) {
    final sorted = values.sorted((a, b) => a.compareTo(b));
    if (sorted.isEmpty) return const Summary(count: 0);
    final mean = sorted.average;
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
    final variance =
        sorted.map((v) => math.pow(v - mean, 2)).sum / sorted.length;
    return Summary(
      count: sorted.length,
      mean: mean,
      median: median,
      min: sorted.first,
      max: sorted.last,
      stdDev: math.sqrt(variance),
    );
  }

  final int count;
  final double? mean;
  final double? median;
  final double? min;
  final double? max;
  final double? stdDev;
}

/// Class-level analytics for one assignment.
class AssignmentStats {
  const new({
    required this.overall,
    required this.letterCounts,
    required this.objectiveMeans,
    required this.groupMeans,
    required this.statusCounts,
    required this.levelCounts,
  });

  /// Only evaluations with a grade of record contribute to [overall],
  /// [objectiveMeans] and [groupMeans]; excused students are left out.
  factory compute(Rubric rubric, Iterable<Evaluation> evals) {
    final results = [
      for (final e in evals) (eval: e, result: Scoring.score(rubric, e)),
    ];
    final graded = results.where((r) => r.result.percent != null).toList();

    final letterCounts = <String, int>{
      for (final band in rubric.scale.bands) band.letter: 0,
    };
    for (final r in graded) {
      letterCounts.update(r.result.letter!, (c) => c + 1, ifAbsent: () => 1);
    }

    Map<String, double?> meansBy(
      Iterable<String> ids,
      Map<String, double?> Function(ScoreResult) pick,
    ) => {
      for (final id in ids)
        id: () {
          final values = graded
              .map((r) => pick(r.result)[id])
              .whereType<double>()
              .toList();
          return values.isEmpty ? null : values.average;
        }(),
    };

    final levelCounts = <String, Map<String, int>>{};
    if (rubric.mode == GradingMode.detailed) {
      for (final objective in rubric.objectives) {
        final counts = {for (final l in rubric.levels) l.id: 0};
        for (final r in results) {
          final score = r.eval.scores[objective.id];
          if (score is LevelScore && counts.containsKey(score.levelId)) {
            counts[score.levelId] = counts[score.levelId]! + 1;
          }
        }
        levelCounts[objective.id] = counts;
      }
    }

    return AssignmentStats(
      overall: Summary.of(graded.map((r) => r.result.percent!)),
      letterCounts: letterCounts,
      objectiveMeans: meansBy(
        rubric.objectives.map((o) => o.id),
        (r) => r.objectivePercents,
      ),
      groupMeans: meansBy(
        rubric.groups.map((g) => g.id),
        (r) => r.groupPercents,
      ),
      statusCounts: {
        for (final s in EvaluationStatus.values)
          s: results.where((r) => r.eval.status == s).length,
      },
      levelCounts: levelCounts,
    );
  }

  final Summary overall;

  /// Every letter in the scale, including those nobody earned.
  final Map<String, int> letterCounts;
  final Map<String, double?> objectiveMeans;
  final Map<String, double?> groupMeans;
  final Map<EvaluationStatus, int> statusCounts;

  /// Detailed rubrics only: objective id → level id → how many students.
  final Map<String, Map<String, int>> levelCounts;

  /// The objective the class did worst on, if any is scored.
  String? get weakestObjectiveId => objectiveMeans.entries
      .where((e) => e.value != null)
      .sorted((a, b) => a.value!.compareTo(b.value!))
      .firstOrNull
      ?.key;

  String? get strongestObjectiveId => objectiveMeans.entries
      .where((e) => e.value != null)
      .sorted((a, b) => b.value!.compareTo(a.value!))
      .firstOrNull
      ?.key;
}

/// Formats 87.456 as "87.5%"; null as an em dash.
String formatPercent(double? value, {int decimals = 1}) {
  if (value == null) return '—';
  final fixed = value.toStringAsFixed(decimals);
  final trimmed = fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
      : fixed;
  return '$trimmed%';
}
