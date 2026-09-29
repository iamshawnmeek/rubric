import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/assignments/assignment_logic.dart';

import '../../helpers/fixtures.dart';

Student _student(String id, String first, String last) =>
    Student(id: id, courseId: 'c1', firstName: first, lastName: last);

Assignment _assignment([Rubric? rubric]) => Assignment(
  id: 'a1',
  courseId: 'c1',
  title: 'Essay 1',
  rubric: rubric ?? essayRubric(),
  sourceRubricId: 'r1',
  createdAt: t0,
);

void main() {
  group('missingEvaluations', () {
    test('creates a notStarted evaluation only for students without one', () {
      final students = [
        _student('s1', 'Ada', 'Lovelace'),
        _student('s2', 'Alan', 'Turing'),
      ];
      final created = missingEvaluations(_assignment(), students, [
        eval(const {}),
      ], now: t0);

      expect(created, hasLength(1));
      expect(created.single.studentId, 's2');
      expect(created.single.assignmentId, 'a1');
      expect(created.single.status, EvaluationStatus.notStarted);
    });
  });

  group('reconcileEvaluation', () {
    test('keeps scores on surviving objectives and drops removed ones', () {
      final original = essayRubric();
      final edited = original.copyWith(
        groups: [
          original.groups[0].copyWith(
            objectives: [original.groups[0].objectives[0]], // o2 removed
          ),
          original.groups[1],
        ],
      );
      final before = eval(const {
        'o1': PercentScore(80),
        'o2': PercentScore(60),
      }).copyWith(objectiveComments: {'o1': 'nice', 'o2': 'gone'});

      final after = reconcileEvaluation(edited, before, now: t0);

      expect(after.scores, {'o1': const PercentScore(80)});
      expect(after.objectiveComments, {'o1': 'nice'});
      expect(after.id, before.id);
      expect(after.status, EvaluationStatus.inProgress);
    });

    test('re-derives status: all remaining objectives scored → complete', () {
      final original = essayRubric();
      final edited = original.copyWith(groups: [original.groups[0]]);
      final before = eval(const {
        'o1': PercentScore(80),
        'o2': PercentScore(60),
      });

      expect(
        reconcileEvaluation(edited, before).status,
        EvaluationStatus.complete,
      );
    });

    test('drops level scores whose level no longer exists', () {
      final rubric = essayRubric(mode: GradingMode.detailed);
      final edited = rubric.copyWith(levels: rubric.levels.take(3).toList());
      final before = eval(const {
        'o1': LevelScore('L4'),
        'o2': LevelScore('L1'),
      });

      expect(reconcileEvaluation(edited, before).scores, {
        'o1': const LevelScore('L4'),
      });
    });

    test('keeps a teacher-set excused mark', () {
      final before = eval(const {}, status: EvaluationStatus.excused);
      expect(
        reconcileEvaluation(essayRubric(), before).status,
        EvaluationStatus.excused,
      );
    });
  });

  test('resnapshot swaps the rubric and reconciles every evaluation', () {
    final library = essayRubric().copyWith(title: 'Essay v2');
    final (updated, evals) = resnapshot(_assignment(), library, [
      eval(const {'o1': PercentScore(70)}),
    ]);
    expect(updated.rubric.title, 'Essay v2');
    expect(updated.id, 'a1');
    expect(evals.single.scores, {'o1': const PercentScore(70)});
  });

  test('snapshotOf strips the template flag', () {
    final template = essayRubric().copyWith(isTemplate: true);
    expect(snapshotOf(template).isTemplate, isFalse);
    expect(snapshotOf(template).id, template.id);
  });

  test('filterRubrics matches title/subject and lists ready ones first', () {
    final ready = essayRubric();
    final broken = essayRubric().copyWith(title: 'Essay draft', groups: []);
    final other = essayRubric().copyWith(title: 'Lab', subject: 'Science');

    expect(filterRubrics([broken, ready, other], 'essay'), [ready, broken]);
    expect(filterRubrics([broken, ready, other], 'SCIENCE'), [other]);
    expect(canAttach(broken), isFalse);
  });

  group('hub rows', () {
    final rubric = essayRubric();
    final students = [
      _student('s1', 'Ada', 'Lovelace'),
      _student('s2', 'Alan', 'Turing'),
      _student('s3', 'Grace', 'Hopper'),
      _student('s4', 'Edsger', 'Dijkstra'),
    ];
    final evaluations = [
      eval(const {
        'o1': PercentScore(100),
        'o2': PercentScore(80),
        'o3': PercentScore(90),
      }, status: EvaluationStatus.complete),
      eval(const {'o1': PercentScore(50)}, student: 's2'),
      eval(const {}, student: 's3', status: EvaluationStatus.missing),
      eval(const {}, student: 's4', status: EvaluationStatus.notStarted),
    ];
    final rows = hubRows(_assignment(rubric), students, evaluations);

    String names(List<HubRow> rows) =>
        rows.map((r) => r.student.firstName).join(',');

    test('pairs students with grades from Scoring', () {
      expect(rows.first.result.percent, 90);
      expect(rows.first.result.letter, 'A');
    });

    test('sorts by name, status and grade', () {
      expect(names(arrangeRows(rows)), 'Edsger,Grace,Ada,Alan');
      expect(
        names(arrangeRows(rows, sort: HubSort.status)),
        'Edsger,Alan,Grace,Ada',
      );
      // Highest first; ungraded last.
      expect(
        names(arrangeRows(rows, sort: HubSort.grade)),
        'Ada,Alan,Grace,Edsger',
      );
    });

    test('filters and searches', () {
      expect(
        names(arrangeRows(rows, filter: HubFilter.ungraded)),
        'Edsger,Alan',
      );
      expect(names(arrangeRows(rows, filter: HubFilter.missing)), 'Grace');
      expect(names(arrangeRows(rows, query: 'turing')), 'Alan');
    });

    test('firstUngraded is the first in name order still to grade', () {
      expect(firstUngraded(rows)?.id, 's4');
      expect(gradedCount(rows), 2);
    });

    test('students without an evaluation yet are left out', () {
      final more = [...students, _student('s5', 'New', 'Kid')];
      expect(hubRows(_assignment(), more, evaluations), hasLength(4));
    });
  });

  test('resetEvaluation blanks the paper but keeps identity', () {
    final before = eval(const {'o1': PercentScore(70)}, penalty: 10);
    final after = resetEvaluation(before, now: t0);
    expect(after.id, before.id);
    expect(after.studentId, before.studentId);
    expect(after.scores, isEmpty);
    expect(after.penaltyPercent, 0);
    expect(after.status, EvaluationStatus.notStarted);
  });
}
