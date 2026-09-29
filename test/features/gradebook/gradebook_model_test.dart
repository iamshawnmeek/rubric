import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/gradebook/gradebook_model.dart';

import '../../helpers/fixtures.dart';

Student student(String id, String first, String last) =>
    Student(id: id, courseId: 'c1', firstName: first, lastName: last);

Assignment assignment(
  String id, {
  DateTime? due,
  DateTime? created,
  Rubric? rubric,
}) => Assignment(
  id: id,
  courseId: 'c1',
  title: 'Assignment $id',
  rubric: rubric ?? essayRubric(),
  dueDate: due,
  createdAt: created ?? t0,
);

/// Every objective at [p]% — so the grade of record is exactly [p].
Evaluation graded(
  String studentId,
  String assignmentId,
  double p, {
  EvaluationStatus status = EvaluationStatus.complete,
}) => Evaluation(
  id: 'e-$studentId-$assignmentId',
  assignmentId: assignmentId,
  studentId: studentId,
  status: status,
  scores: {'o1': PercentScore(p), 'o2': PercentScore(p), 'o3': PercentScore(p)},
  updatedAt: t0,
);

Evaluation marked(String studentId, String assignmentId, EvaluationStatus s) =>
    Evaluation(
      id: 'e-$studentId-$assignmentId',
      assignmentId: assignmentId,
      studentId: studentId,
      status: s,
      updatedAt: t0,
    );

void main() {
  final ada = student('s1', 'Ada', 'Lovelace');
  final alan = student('s2', 'Alan', 'Turing');
  final grace = student('s3', 'Grace', 'Hopper');
  final a1 = assignment('a1', due: DateTime(2026, 9, 5));
  final a2 = assignment('a2', due: DateTime(2026, 9, 12));
  final a3 = assignment('a3', due: DateTime(2026, 9, 19));

  group('cells', () {
    test('status and grade of record per evaluation state', () {
      final gb = Gradebook.build(
        students: [ada],
        assignments: [a1, a2, a3],
        evaluations: [
          graded('s1', 'a1', 80),
          marked('s1', 'a2', EvaluationStatus.excused),
        ],
      );
      final cells = gb.rows.single.cells;
      expect(cells[0].status, CellStatus.graded);
      expect(cells[0].percent, 80);
      expect(cells[1].status, CellStatus.excused);
      expect(cells[1].percent, isNull);
      expect(cells[2].status, CellStatus.notGraded);
      expect(cells[2].counts, isFalse);
    });

    test('missing with no score counts as zero; a scored missing keeps it', () {
      final gb = Gradebook.build(
        students: [ada, alan],
        assignments: [a1],
        evaluations: [
          marked('s1', 'a1', EvaluationStatus.missing),
          graded('s2', 'a1', 70, status: EvaluationStatus.missing),
        ],
      );
      expect(gb.rowFor('s1')!.cells.single.status, CellStatus.missing);
      expect(gb.rowFor('s1')!.cells.single.percent, 0);
      expect(gb.rowFor('s2')!.cells.single.percent, 70);
    });

    test('a partly scored paper is in progress with a running grade', () {
      final gb = Gradebook.build(
        students: [ada],
        assignments: [a1],
        evaluations: [
          Evaluation(
            id: 'e',
            assignmentId: 'a1',
            studentId: 's1',
            status: EvaluationStatus.inProgress,
            scores: const {'o1': PercentScore(50)},
            updatedAt: t0,
          ),
        ],
      );
      final cell = gb.rows.single.cells.single;
      expect(cell.status, CellStatus.inProgress);
      expect(cell.percent, 50);
    });

    test('a started paper with nothing scored is not graded', () {
      final gb = Gradebook.build(
        students: [ada],
        assignments: [a1],
        evaluations: [marked('s1', 'a1', EvaluationStatus.inProgress)],
      );
      expect(gb.rows.single.cells.single.status, CellStatus.notGraded);
    });
  });

  group('averages', () {
    final gb = Gradebook.build(
      students: [ada, alan, grace],
      assignments: [a3, a1, a2],
      evaluations: [
        graded('s1', 'a1', 90),
        marked('s1', 'a2', EvaluationStatus.excused),
        graded('s1', 'a3', 70),
        graded('s2', 'a1', 60),
        marked('s2', 'a2', EvaluationStatus.missing),
        // Grace: nothing graded.
        marked('s3', 'a1', EvaluationStatus.notStarted),
        // Not on the roster — ignored.
        graded('ghost', 'a1', 0),
      ],
    );

    test('student average ignores excused and ungraded, missing is 0', () {
      expect(gb.rowFor('s1')!.average, 80);
      expect(gb.rowFor('s2')!.average, 30);
      expect(gb.rowFor('s3')!.average, isNull);
      expect(gb.rowFor('s1')!.gradedCount, 2);
      expect(gb.rowFor('s2')!.missingCount, 1);
    });

    test('assignments are equally weighted regardless of points', () {
      final big = assignment(
        'big',
        due: DateTime(2026, 9, 6),
      ).copyWith(pointsPossible: 500);
      final small = assignment(
        'small',
        due: DateTime(2026, 9, 7),
      ).copyWith(pointsPossible: 10);
      final g = Gradebook.build(
        students: [ada],
        assignments: [big, small],
        evaluations: [graded('s1', 'big', 100), graded('s1', 'small', 50)],
      );
      expect(g.rows.single.average, 75);
    });

    test('per-assignment mean covers only the cells that count', () {
      expect(gb.summaryFor('a1').mean, 75);
      expect(gb.summaryFor('a1').count, 2);
      expect(gb.summaryFor('a2').mean, 0);
      expect(gb.summaryFor('a3').mean, 70);
    });

    test('class average is the mean of student averages', () {
      expect(gb.studentAverages, [80, 30]);
      expect(gb.classAverage, 55);
    });

    test('assignments are ordered by due date, then created', () {
      expect(gb.assignments.map((a) => a.id), ['a1', 'a2', 'a3']);
      final undated = assignment('u', created: DateTime(2026, 9, 8));
      expect(chronological([a2, undated, a1]).map((a) => a.id), [
        'a1',
        'u',
        'a2',
      ]);
    });

    test('rows sort by name and by average, no-average last', () {
      expect(gb.sorted(GradebookSort.name).map((r) => r.student.id), [
        's3',
        's1',
        's2',
      ]);
      expect(
        gb
            .sorted(GradebookSort.name, descending: true)
            .map((r) => r.student.id),
        ['s2', 's1', 's3'],
      );
      expect(gb.sorted(GradebookSort.average).map((r) => r.student.id), [
        's1',
        's2',
        's3',
      ]);
      expect(
        gb
            .sorted(GradebookSort.average, descending: true)
            .map((r) => r.student.id),
        ['s2', 's1', 's3'],
      );
    });

    test('class trend skips assignments nobody has a grade on', () {
      final trend = gb.classTrend;
      expect(trend.map((p) => p.assignment.id), ['a1', 'a2', 'a3']);
      expect(trend.map((p) => p.percent), [75, 0, 70]);
      expect(
        Gradebook.build(
          students: [ada],
          assignments: [a1, a2],
          evaluations: [graded('s1', 'a2', 88)],
        ).classTrend.map((p) => p.assignment.id),
        ['a2'],
      );
    });

    test('student trend is their counted grades in order', () {
      expect(gb.studentTrend('s1').map((p) => p.percent), [90, 70]);
      expect(gb.studentTrend('nobody'), isEmpty);
    });
  });

  group('scale, histogram, letters, tiers', () {
    test('course scale is the most used, ties to the latest', () {
      final pm = essayRubric().copyWith(scale: GradingScale.plusMinus);
      final x = assignment('x', due: DateTime(2026, 9));
      final y = assignment('y', due: DateTime(2026, 9, 2), rubric: pm);
      final z = assignment('z', due: DateTime(2026, 9, 3), rubric: pm);
      expect(courseScale([x, y, z]), GradingScale.plusMinus);
      expect(courseScale([x, y]), GradingScale.plusMinus);
      expect(courseScale([y, x]), GradingScale.standard);
      expect(courseScale([]), GradingScale.standard);
    });

    test('histogram buckets by ten with 100 in the top bucket', () {
      expect(histogram([0, 9.99, 10, 55, 90, 100, 120, -5]), [
        3, 1, 0, 0, 0, 1, 0, 0, 0, 3, //
      ]);
      expect(histogram([], bins: 5), [0, 0, 0, 0, 0]);
    });

    test('letter distribution includes unearned letters', () {
      expect(letterDistribution([95, 91, 85, 12], GradingScale.standard), {
        'A': 2,
        'B': 1,
        'C': 0,
        'D': 0,
        'F': 1,
      });
    });

    test('grade tiers', () {
      expect(<double>[95, 90, 89.9, 80, 75, 60, 59.9, 0].map(gradeTier), [
        4, 4, 3, 3, 2, 1, 0, 0, //
      ]);
    });
  });

  group('needs attention', () {
    test('flags two or more missing, and a drop of at least 5 points', () {
      final gb = Gradebook.build(
        students: [ada, alan, grace],
        assignments: [a1, a2, a3],
        evaluations: [
          // Ada: 90, 90, 60 → average 80 after being 90: a 10-point drop.
          graded('s1', 'a1', 90),
          graded('s1', 'a2', 90),
          graded('s1', 'a3', 60),
          // Alan: two missing.
          graded('s2', 'a1', 100),
          marked('s2', 'a2', EvaluationStatus.missing),
          marked('s2', 'a3', EvaluationStatus.missing),
          // Grace: steady, one missing, small drop (90 → 88).
          graded('s3', 'a1', 90),
          graded('s3', 'a2', 86),
        ],
      );
      final items = needsAttention(gb);
      expect(items.map((i) => i.row.student.id), ['s2', 's1']);
      expect(items[0].missing, 2);
      expect(items[1].drop, closeTo(10, 1e-9));
    });

    test('a rise or a single grade is never a drop', () {
      final gb = Gradebook.build(
        students: [ada, alan],
        assignments: [a1, a2],
        evaluations: [
          graded('s1', 'a1', 50),
          graded('s1', 'a2', 100),
          graded('s2', 'a1', 10),
        ],
      );
      expect(gb.rowFor('s1')!.latestDrop, lessThan(0));
      expect(gb.rowFor('s2')!.latestDrop, isNull);
      expect(needsAttention(gb), isEmpty);
    });
  });

  group('objectives', () {
    Evaluation scores(String s, String a, double o1, double o2, double o3) =>
        Evaluation(
          id: 'e-$s-$a',
          assignmentId: a,
          studentId: s,
          status: EvaluationStatus.complete,
          scores: {
            'o1': PercentScore(o1),
            'o2': PercentScore(o2),
            'o3': PercentScore(o3),
          },
          updatedAt: t0,
        );

    // A second rubric that renames ids but shares "Grammar" (case differs)
    // and adds "Voice".
    final other = Rubric(
      id: 'r2',
      title: 'Story',
      createdAt: t0,
      updatedAt: t0,
      groups: const [
        RubricGroup(
          id: 'g',
          title: 'All',
          weight: 100,
          objectives: [
            Objective(id: 'x1', title: ' grammar '),
            Objective(id: 'x2', title: 'Voice'),
          ],
        ),
      ],
    );
    final b = assignment('b', due: DateTime(2026, 9, 30), rubric: other);

    final gb = Gradebook.build(
      students: [ada, alan, grace],
      assignments: [a1, b],
      evaluations: [
        scores('s1', 'a1', 100, 80, 60),
        scores('s2', 'a1', 60, 40, 20),
        marked('s3', 'a1', EvaluationStatus.excused),
        Evaluation(
          id: 'e-s1-b',
          assignmentId: 'b',
          studentId: 's1',
          status: EvaluationStatus.complete,
          scores: const {'x1': PercentScore(90), 'x2': PercentScore(70)},
          updatedAt: t0,
        ),
      ],
    );

    test('mastery merges objectives by title across assignments', () {
      final m = objectiveMastery(gb);
      expect(m.map((o) => o.title), [
        'Grammar',
        'Organization',
        'Sources',
        'Voice',
      ]);
      final grammar = m.first;
      expect(grammar.means, {'a1': 80, 'b': 90});
      expect(grammar.overall, 85);
      expect(m.last.means, {'b': 70});
      expect(m[1].means.containsKey('b'), isFalse);
    });

    test('an objective nobody is graded on yet has a null mean', () {
      final m = objectiveMastery(
        Gradebook.build(students: [ada], assignments: [a1], evaluations: []),
      );
      expect(m.first.means, {'a1': null});
      expect(m.first.overall, isNull);
    });

    test('student objectives compare with the class on the same work', () {
      final alanVs = studentObjectives(gb, 's2');
      // Alan only did a1: class means there are 80/60/40.
      expect(alanVs.map((c) => c.title), [
        'Grammar',
        'Organization',
        'Sources',
      ]);
      expect(alanVs.first.student, 60);
      expect(alanVs.first.classMean, 80);
      expect(alanVs.first.delta, -20);

      final adaVs = studentObjectives(gb, 's1');
      final grammar = adaVs.firstWhere((c) => c.title == 'Grammar');
      expect(grammar.student, 95);
      expect(grammar.classMean, 85);
      expect(adaVs.first.delta, greaterThanOrEqualTo(adaVs.last.delta));

      expect(studentObjectives(gb, 's3'), isEmpty);
      expect(studentObjectives(gb, 'nobody'), isEmpty);
    });
  });
}
