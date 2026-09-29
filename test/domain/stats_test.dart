import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/stats.dart';

import '../helpers/fixtures.dart';

void main() {
  test('Summary of an empty set is empty, not zero', () {
    final s = Summary.of([]);
    expect(s.count, 0);
    expect(s.mean, isNull);
    expect(s.median, isNull);
  });

  test('Summary basics', () {
    final s = Summary.of([90, 70, 80, 100]);
    expect(s.count, 4);
    expect(s.mean, 85);
    expect(s.median, 85);
    expect(s.min, 70);
    expect(s.max, 100);
    expect(s.stdDev, closeTo(11.1803, 1e-3));
    expect(Summary.of([3, 1, 2]).median, 2);
  });

  group('AssignmentStats', () {
    final rubric = essayRubric(mode: GradingMode.detailed);
    final evals = [
      eval({
        'o1': const LevelScore('L4'),
        'o2': const LevelScore('L4'),
        'o3': const LevelScore('L4'),
      }, student: 'a'),
      eval({
        'o1': const LevelScore('L2'),
        'o2': const LevelScore('L2'),
        'o3': const LevelScore('L2'),
      }, student: 'b'),
      eval({}, student: 'c', status: EvaluationStatus.excused),
      eval({}, student: 'd', status: EvaluationStatus.notStarted),
    ];
    final stats = AssignmentStats.compute(rubric, evals);

    test('overall only counts graded students', () {
      expect(stats.overall.count, 2);
      expect(stats.overall.mean, 75);
    });

    test('letter counts include letters nobody earned', () {
      expect(stats.letterCounts, {'A': 1, 'B': 0, 'C': 0, 'D': 0, 'F': 1});
    });

    test('objective and group means', () {
      expect(stats.objectiveMeans['o1'], 75);
      expect(stats.groupMeans['g2'], 75);
    });

    test('status and level distributions', () {
      expect(stats.statusCounts[EvaluationStatus.excused], 1);
      expect(stats.statusCounts[EvaluationStatus.notStarted], 1);
      expect(stats.levelCounts['o1'], {'L4': 1, 'L3': 0, 'L2': 1, 'L1': 0});
    });

    test('weakest and strongest objective', () {
      final mixed = AssignmentStats.compute(essayRubric(), [
        eval({
          'o1': const PercentScore(90),
          'o2': const PercentScore(40),
          'o3': const PercentScore(70),
        }),
      ]);
      expect(mixed.weakestObjectiveId, 'o2');
      expect(mixed.strongestObjectiveId, 'o1');
      expect(
        AssignmentStats.compute(essayRubric(), []).weakestObjectiveId,
        isNull,
      );
    });
  });

  test('formatPercent', () {
    expect(formatPercent(null), '—');
    expect(formatPercent(87.456), '87.5%');
    expect(formatPercent(90), '90%');
    expect(formatPercent(90.04), '90%');
    expect(formatPercent(66.666, decimals: 2), '66.67%');
  });
}
