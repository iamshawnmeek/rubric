import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/scoring.dart';

import '../helpers/fixtures.dart';

void main() {
  group('Scoring.score (simple)', () {
    test('weights group means by group weight', () {
      // Writing mean (80+100)/2 = 90 → ×60; Research 50 → ×40. 54+20 = 74.
      final r = Scoring.score(
        essayRubric(),
        eval({
          'o1': const PercentScore(80),
          'o2': const PercentScore(100),
          'o3': const PercentScore(50),
        }),
      );
      expect(r.percent, closeTo(74, 1e-9));
      expect(r.letter, 'C');
      expect(r.groupPercents, {'g1': 90.0, 'g2': 50.0});
      expect(r.isComplete, isTrue);
      expect(r.scoredCount, 3);
    });

    test('partial grading averages only the groups that have scores', () {
      final r = Scoring.score(
        essayRubric(),
        eval({'o1': const PercentScore(70)}),
      );
      // Only Writing is scored, and within it only o1: the running grade is 70,
      // not 70 × 60/100 = 42 — an unscored group must not read as zero.
      expect(r.percent, closeTo(70, 1e-9));
      expect(r.groupPercents['g2'], isNull);
      expect(r.objectivePercents['o2'], isNull);
      expect(r.isComplete, isFalse);
      expect(r.progress, closeTo(1 / 3, 1e-9));
    });

    test('nothing scored yields no grade, not zero', () {
      final r = Scoring.score(essayRubric(), eval({}));
      expect(r.percent, isNull);
      expect(r.letter, isNull);
    });

    test('missing with no scores counts as zero', () {
      final r = Scoring.score(
        essayRubric(),
        eval({}, status: EvaluationStatus.missing),
      );
      expect(r.percent, 0);
      expect(r.letter, 'F');
    });

    test('excused never has a grade even with scores or override', () {
      final r = Scoring.score(
        essayRubric(),
        eval(
          {'o1': const PercentScore(100)},
          status: EvaluationStatus.excused,
          override: 95,
        ),
      );
      expect(r.percent, isNull);
    });

    test('penalty deducts points and clamps at zero', () {
      final all100 = {
        'o1': const PercentScore(100),
        'o2': const PercentScore(100),
        'o3': const PercentScore(100),
      };
      expect(
        Scoring.score(essayRubric(), eval(all100, penalty: 15)).percent,
        85,
      );
      final low = {
        'o1': const PercentScore(5),
        'o2': const PercentScore(5),
        'o3': const PercentScore(5),
      };
      expect(Scoring.score(essayRubric(), eval(low, penalty: 50)).percent, 0);
    });

    test('override replaces the computed grade but keeps rawPercent', () {
      final r = Scoring.score(
        essayRubric(),
        eval({'o1': const PercentScore(40)}, override: 88),
      );
      expect(r.rawPercent, 40);
      expect(r.percent, 88);
      expect(r.letter, 'B');
    });

    test('out-of-range percents are clamped', () {
      final r = Scoring.score(
        essayRubric(),
        eval({'o3': const PercentScore(140)}),
      );
      expect(r.objectivePercents['o3'], 100);
    });
  });

  group('Scoring.score (detailed)', () {
    final rubric = essayRubric(mode: GradingMode.detailed);

    test('a level scores as points over the top level', () {
      final r = Scoring.score(
        rubric,
        eval({
          'o1': const LevelScore('L4'),
          'o2': const LevelScore('L2'),
          'o3': const LevelScore('L3'),
        }),
      );
      // Writing (100+50)/2 = 75 ×.6 = 45; Research 75 ×.4 = 30 → 75.
      expect(r.objectivePercents, {'o1': 100.0, 'o2': 50.0, 'o3': 75.0});
      expect(r.percent, closeTo(75, 1e-9));
    });

    test('a level that no longer exists reads as unscored', () {
      final r = Scoring.score(rubric, eval({'o1': const LevelScore('gone')}));
      expect(r.objectivePercents['o1'], isNull);
      expect(r.scoredCount, 0);
      expect(r.percent, isNull);
    });
  });

  group('Scoring.derivedStatus', () {
    final rubric = essayRubric();

    test('tracks progress from scores', () {
      expect(
        Scoring.derivedStatus(rubric, eval({})),
        EvaluationStatus.notStarted,
      );
      expect(
        Scoring.derivedStatus(rubric, eval({'o1': const PercentScore(1)})),
        EvaluationStatus.inProgress,
      );
      expect(
        Scoring.derivedStatus(
          rubric,
          eval({
            'o1': const PercentScore(1),
            'o2': const PercentScore(1),
            'o3': const PercentScore(1),
          }),
        ),
        EvaluationStatus.complete,
      );
    });

    test('keeps excused; keeps missing only while unscored', () {
      expect(
        Scoring.derivedStatus(
          rubric,
          eval({'o1': const PercentScore(1)}, status: EvaluationStatus.excused),
        ),
        EvaluationStatus.excused,
      );
      expect(
        Scoring.derivedStatus(
          rubric,
          eval({}, status: EvaluationStatus.missing),
        ),
        EvaluationStatus.missing,
      );
      expect(
        Scoring.derivedStatus(
          rubric,
          eval({'o1': const PercentScore(1)}, status: EvaluationStatus.missing),
        ),
        EvaluationStatus.inProgress,
      );
    });

    test('ignores scores for objectives no longer on the rubric', () {
      expect(
        Scoring.derivedStatus(rubric, eval({'stale': const PercentScore(90)})),
        EvaluationStatus.notStarted,
      );
    });
  });

  test('points scales the grade of record', () {
    final r = Scoring.score(
      essayRubric(),
      eval({
        'o1': const PercentScore(100),
        'o2': const PercentScore(100),
        'o3': const PercentScore(50),
      }),
    );
    expect(Scoring.points(r, 50), closeTo(40, 1e-9));
  });
}
