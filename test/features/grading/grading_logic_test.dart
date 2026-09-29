import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/features/grading/comment_bank_logic.dart';
import 'package:rubric/features/grading/grading_logic.dart';

import '../../helpers/fixtures.dart';

Student _s(String id, String first, String last) =>
    Student(id: id, courseId: 'c1', firstName: first, lastName: last);

void main() {
  final rubric = essayRubric();
  final detailed = essayRubric(mode: GradingMode.detailed);
  final blank = eval(const {}, status: EvaluationStatus.notStarted);

  group('setScore', () {
    test('first score moves notStarted to inProgress, all scores to '
        'complete', () {
      final one = GradingLogic.setScore(
        rubric,
        blank,
        'o1',
        const PercentScore(90),
      );
      expect(one.status, EvaluationStatus.inProgress);
      final all = GradingLogic.setScore(
        rubric,
        GradingLogic.setScore(rubric, one, 'o2', const PercentScore(80)),
        'o3',
        const PercentScore(70),
      );
      expect(all.status, EvaluationStatus.complete);
      // Writing 85 (60%) and Research 70 (40%) → 79.
      expect(Scoring.score(rubric, all).percent, closeTo(79, 1e-9));
    });

    test('clearing the only score returns to notStarted', () {
      final one = GradingLogic.setScore(
        rubric,
        blank,
        'o1',
        const PercentScore(90),
      );
      final cleared = GradingLogic.setScore(rubric, one, 'o1', null);
      expect(cleared.scores, isEmpty);
      expect(cleared.status, EvaluationStatus.notStarted);
    });

    test('scoring a missing paper means it was handed in', () {
      final missing = GradingLogic.setMissing(rubric, blank, missing: true);
      final scored = GradingLogic.setScore(
        rubric,
        missing,
        'o1',
        const PercentScore(60),
      );
      expect(scored.status, EvaluationStatus.inProgress);
    });

    test('scoring an excused student keeps them excused', () {
      final excused = GradingLogic.setExcused(rubric, blank, excused: true);
      final scored = GradingLogic.setScore(
        rubric,
        excused,
        'o1',
        const PercentScore(60),
      );
      expect(scored.status, EvaluationStatus.excused);
      expect(Scoring.score(rubric, scored).percent, isNull);
    });
  });

  group('toggleLevel', () {
    test('selects, switches and clears on a second tap', () {
      final a = GradingLogic.toggleLevel(detailed, blank, 'o1', 'L4');
      expect(a.scores['o1'], const LevelScore('L4'));
      final b = GradingLogic.toggleLevel(detailed, a, 'o1', 'L2');
      expect(b.scores['o1'], const LevelScore('L2'));
      final c = GradingLogic.toggleLevel(detailed, b, 'o1', 'L2');
      expect(c.scores.containsKey('o1'), isFalse);
      expect(c.status, EvaluationStatus.notStarted);
    });
  });

  group('missing and excused', () {
    test('missing with no scores counts as zero', () {
      final m = GradingLogic.setMissing(rubric, blank, missing: true);
      expect(m.status, EvaluationStatus.missing);
      expect(Scoring.score(rubric, m).percent, 0);
    });

    test('un-marking reverts to the status the scores imply', () {
      final scored = GradingLogic.setScore(
        rubric,
        blank,
        'o1',
        const PercentScore(90),
      );
      final ex = GradingLogic.setExcused(rubric, scored, excused: true);
      expect(ex.status, EvaluationStatus.excused);
      final back = GradingLogic.setExcused(rubric, ex, excused: false);
      expect(back.status, EvaluationStatus.inProgress);
      expect(back.scores, scored.scores);

      final m = GradingLogic.setMissing(rubric, blank, missing: true);
      expect(
        GradingLogic.setMissing(rubric, m, missing: false).status,
        EvaluationStatus.notStarted,
      );
    });

    test('marking missing replaces excused and vice versa', () {
      final ex = GradingLogic.setExcused(rubric, blank, excused: true);
      final m = GradingLogic.setMissing(rubric, ex, missing: true);
      expect(m.status, EvaluationStatus.missing);
      expect(
        GradingLogic.setExcused(rubric, m, excused: true).status,
        EvaluationStatus.excused,
      );
    });
  });

  group('late and penalty', () {
    final full = eval(const {
      'o1': PercentScore(90),
      'o2': PercentScore(90),
      'o3': PercentScore(90),
    }, status: EvaluationStatus.complete);

    test('late applies the default penalty to the grade', () {
      final late = GradingLogic.setLate(full, late: true, defaultPenalty: 10);
      expect(late.late, isTrue);
      expect(late.penaltyPercent, 10);
      expect(Scoring.score(rubric, late).percent, closeTo(80, 1e-9));
    });

    test('an edited penalty survives toggling late on again', () {
      final edited = GradingLogic.setPenalty(
        GradingLogic.setLate(full, late: true, defaultPenalty: 10),
        25,
      );
      final again = GradingLogic.setLate(
        edited,
        late: true,
        defaultPenalty: 10,
      );
      expect(again.penaltyPercent, 25);
    });

    test('turning late off removes the penalty', () {
      final late = GradingLogic.setLate(full, late: true, defaultPenalty: 10);
      final onTime = GradingLogic.setLate(
        late,
        late: false,
        defaultPenalty: 10,
      );
      expect(onTime.penaltyPercent, 0);
      expect(Scoring.score(rubric, onTime).percent, closeTo(90, 1e-9));
    });

    test('penalty is clamped to 0–100', () {
      expect(GradingLogic.setPenalty(full, 140).penaltyPercent, 100);
      expect(GradingLogic.setPenalty(full, -5).penaltyPercent, 0);
    });

    test('override beats the penalty; clearing restores it', () {
      final late = GradingLogic.setLate(full, late: true, defaultPenalty: 10);
      final over = GradingLogic.setOverride(late, 95, reason: '  Retake  ');
      expect(over.overrideReason, 'Retake');
      expect(Scoring.score(rubric, over).percent, 95);
      final cleared = GradingLogic.setOverride(over, null);
      expect(cleared.overridePercent, isNull);
      expect(cleared.overrideReason, '');
      expect(Scoring.score(rubric, cleared).percent, closeTo(80, 1e-9));
    });

    test('override is clamped', () {
      expect(GradingLogic.setOverride(full, 130).overridePercent, 100);
    });
  });

  group('comments', () {
    test('objective comment is removed when blanked', () {
      final c = GradingLogic.setObjectiveComment(blank, 'o1', 'Nice');
      expect(c.objectiveComments, {'o1': 'Nice'});
      expect(
        GradingLogic.setObjectiveComment(c, 'o1', '  ').objectiveComments,
        isEmpty,
      );
    });

    test('insertSnippet appends with a single space', () {
      expect(GradingLogic.insertSnippet('', ' Great work. '), 'Great work.');
      expect(
        GradingLogic.insertSnippet('Good thesis.  ', 'Cite sources.'),
        'Good thesis. Cite sources.',
      );
    });
  });

  test('parsePercent reads typed values and rejects junk', () {
    expect(GradingLogic.parsePercent('87.5'), 87.5);
    expect(GradingLogic.parsePercent('90%'), 90);
    expect(GradingLogic.parsePercent('250'), 100);
    expect(GradingLogic.parsePercent('abc'), isNull);
    expect(GradingLogic.parsePercent(''), isNull);
  });

  group('roster navigation', () {
    // Deliberately out of order: compareStudents sorts by last then first.
    final roster = [
      _s('c', 'Cara', 'Zed'),
      _s('a', 'Ada', 'Lovelace'),
      _s('b', 'Alan', 'Turing'),
      _s('d', 'Bob', 'Lovelace'),
    ]..sort(compareStudents);

    test('roster order is by last then first name', () {
      expect(roster.map((s) => s.id), ['a', 'd', 'b', 'c']);
    });

    test('neighbour steps along the roster and stops at the ends', () {
      expect(GradingLogic.neighbour(roster, 'a', forward: true), 'd');
      expect(GradingLogic.neighbour(roster, 'd', forward: false), 'a');
      expect(GradingLogic.neighbour(roster, 'a', forward: false), isNull);
      expect(GradingLogic.neighbour(roster, 'c', forward: true), isNull);
    });

    Evaluation done(String student) => eval(const {
      'o1': PercentScore(90),
      'o2': PercentScore(90),
      'o3': PercentScore(90),
    }, student: student);

    test('nextUngraded looks after the current student and wraps', () {
      final byStudent = {'d': done('d'), 'b': done('b')};
      // After 'd': b graded, c ungraded.
      expect(GradingLogic.nextUngraded(rubric, roster, byStudent, 'd'), 'c');
      // After 'c': wraps to a.
      expect(GradingLogic.nextUngraded(rubric, roster, byStudent, 'c'), 'a');
    });

    test('in-progress is ungraded; excused, missing and override are '
        'graded', () {
      final byStudent = {
        'a': eval(const {'o1': PercentScore(50)}, student: 'a'),
        'd': eval(const {}, student: 'd', status: EvaluationStatus.excused),
        'b': eval(const {}, student: 'b', status: EvaluationStatus.missing),
        'c': eval(
          const {},
          student: 'c',
          status: EvaluationStatus.notStarted,
          override: 88,
        ),
      };
      expect(
        GradingLogic.nextUngraded(rubric, roster, byStudent, 'a'),
        'a',
        reason: 'only the current student is left',
      );
      expect(GradingLogic.allGraded(rubric, roster, byStudent), isFalse);
      byStudent['a'] = done('a');
      expect(GradingLogic.nextUngraded(rubric, roster, byStudent, 'a'), isNull);
      expect(GradingLogic.allGraded(rubric, roster, byStudent), isTrue);
    });

    test('classAverage leaves out excused and ungraded students', () {
      final byStudent = {
        'a': eval(const {
          'o1': PercentScore(100),
          'o2': PercentScore(100),
          'o3': PercentScore(100),
        }, student: 'a'),
        'd': eval(const {
          'o1': PercentScore(60),
          'o2': PercentScore(60),
          'o3': PercentScore(60),
        }, student: 'd'),
        'b': eval(const {}, student: 'b', status: EvaluationStatus.excused),
      };
      expect(
        GradingLogic.classAverage(rubric, roster, byStudent),
        closeTo(80, 1e-9),
      );
    });
  });

  group('CommentBankLogic', () {
    const bank = [
      CommentSnippet(
        id: '1',
        text: 'Great thesis statement',
        category: 'Praise',
      ),
      CommentSnippet(id: '2', text: 'Cite your sources', category: 'Research'),
      CommentSnippet(id: '3', text: 'Proofread for typos'),
    ];

    test('filter matches every word in text or category, keeping order', () {
      expect(CommentBankLogic.filter(bank, '').map((s) => s.id), [
        '1',
        '2',
        '3',
      ]);
      expect(CommentBankLogic.filter(bank, 'SOURCES').map((s) => s.id), ['2']);
      expect(CommentBankLogic.filter(bank, 'praise thesis').map((s) => s.id), [
        '1',
      ]);
      expect(CommentBankLogic.filter(bank, 'praise typos'), isEmpty);
    });

    test('filter by category; empty string means uncategorised', () {
      expect(
        CommentBankLogic.filter(
          bank,
          '',
          category: 'Research',
        ).map((s) => s.id),
        ['2'],
      );
      expect(CommentBankLogic.filter(bank, '', category: '').map((s) => s.id), [
        '3',
      ]);
    });

    test('categories are distinct and sorted', () {
      expect(CommentBankLogic.categories(bank), ['Praise', 'Research']);
    });

    test('contains ignores case and spacing', () {
      expect(CommentBankLogic.contains(bank, '  cite YOUR   sources '), isTrue);
      expect(CommentBankLogic.contains(bank, 'something new'), isFalse);
      expect(CommentBankLogic.contains(bank, '   '), isFalse);
    });
  });
}
