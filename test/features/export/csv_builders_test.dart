import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/export/csv_builders.dart';
import 'package:rubric/features/export/export_actions.dart';

import '../../helpers/export_fakes.dart';
import '../../helpers/fixtures.dart';

Assignment _assignment({
  GradingMode mode = GradingMode.simple,
  String id = 'a1',
  String title = 'Essay',
  double points = 100,
  DateTime? due,
}) => Assignment(
  id: id,
  courseId: 'c1',
  title: title,
  rubric: essayRubric(mode: mode),
  pointsPossible: points,
  dueDate: due,
  createdAt: t0,
);

Student _student(String id, String first, String last, {String number = ''}) =>
    Student(
      id: id,
      courseId: 'c1',
      firstName: first,
      lastName: last,
      studentNumber: number,
    );

/// Strips the BOM and parses the CSV back into cells.
List<List<String>> _cells(String csv) {
  expect(csv.startsWith('﻿'), isTrue, reason: 'UTF-8 BOM for Excel');
  return [
    for (final row in Csv().decode(csv.substring(1)))
      [for (final cell in row) '$cell'],
  ];
}

void main() {
  group('buildAssignmentCsv', () {
    test('columns: identity, status, objectives, groups, totals', () {
      final csv = buildAssignmentCsv(
        l10n: l10nEn,
        assignment: _assignment(),
        students: const [],
        evaluations: const [],
      );
      expect(_cells(csv).single, [
        'Last name',
        'First name',
        'Student #',
        'Status',
        'Grammar',
        'Organization',
        'Sources',
        'Writing %',
        'Research %',
        'Final %',
        'Letter',
        'Points (of 100)',
        'Comment',
      ]);
    });

    test('one row per student, sorted by last name, with computed grades', () {
      final csv = buildAssignmentCsv(
        l10n: l10nEn,
        assignment: _assignment(points: 50),
        students: [
          _student('s2', 'Zed', 'Young', number: '002'),
          _student('s1', 'Ada', 'Lovelace', number: '001'),
        ],
        evaluations: [
          eval(const {
            'o1': PercentScore(80),
            'o2': PercentScore(60),
            'o3': PercentScore(100),
          }, status: EvaluationStatus.complete),
        ],
      );
      final rows = _cells(csv);
      expect(rows, hasLength(3));
      // Writing = mean(80, 60) = 70; final = .6·70 + .4·100 = 82 → B;
      // 82% of 50 points = 41.
      expect(rows[1], [
        'Lovelace',
        'Ada',
        '001',
        'Complete',
        '80',
        '60',
        '100',
        '70',
        '100',
        '82',
        'B',
        '41',
        '',
      ]);
      expect(rows[2].take(4), ['Young', 'Zed', '002', 'Not started']);
      expect(rows[2].skip(4).every((c) => c.isEmpty), isTrue);
    });

    test('detailed rubrics export the level label per objective', () {
      final csv = buildAssignmentCsv(
        l10n: l10nEn,
        assignment: _assignment(mode: GradingMode.detailed),
        students: [_student('s1', 'Ada', 'Lovelace')],
        evaluations: [
          eval(const {'o1': LevelScore('L4'), 'o3': LevelScore('L2')}),
        ],
      );
      final row = _cells(csv)[1];
      expect(row.sublist(4, 7), ['Exemplary', '', 'Developing']);
    });

    test('quotes commas, quotes and newlines; defuses formulas', () {
      final csv = buildAssignmentCsv(
        l10n: l10nEn,
        assignment: _assignment(),
        students: [_student('s1', 'Ann "AJ"', "O'Neil, Jr")],
        evaluations: [
          eval(const {}).copyWith(comment: 'Great work,\nsee "notes"'),
          eval(const {}, student: 's9'),
        ],
      );
      expect(csv, contains('"O\'Neil, Jr","Ann ""AJ"""'));
      expect(csv, contains('"Great work,\nsee ""notes"""'));
      expect(_cells(csv)[1].last, 'Great work,\nsee "notes"');

      final injected = buildAssignmentCsv(
        l10n: l10nEn,
        assignment: _assignment(),
        students: [_student('s1', '=HYPERLINK("x")', '@Evil')],
        evaluations: const [],
      );
      final row = _cells(injected)[1];
      expect(row[0], "'@Evil");
      expect(row[1], "'=HYPERLINK(\"x\")");
    });

    test('rows end with CRLF for Excel', () {
      final csv = buildAssignmentCsv(
        l10n: l10nEn,
        assignment: _assignment(),
        students: [_student('s1', 'Ada', 'Lovelace')],
        evaluations: const [],
      );
      expect(csv, contains('Comment\r\nLovelace'));
    });
  });

  group('buildGradebookCsv', () {
    test('students × assignments with ISO due dates and an average', () {
      final essay = _assignment(due: DateTime(2026, 9, 12));
      final quiz = _assignment(id: 'a2', title: 'Quiz', points: 25);
      final csv = buildGradebookCsv(
        l10n: l10nEn,
        assignments: [essay, quiz],
        students: [
          _student('s1', 'Ada', 'Lovelace'),
          _student('s2', 'Zed', 'Young'),
        ],
        evaluations: [
          eval(const {}, override: 90),
          Evaluation(
            id: 'q1',
            assignmentId: 'a2',
            studentId: 's1',
            overridePercent: 40,
            updatedAt: t0,
          ),
          eval(
            const {},
            student: 's2',
            status: EvaluationStatus.excused,
            override: 10,
          ),
        ],
      );
      final rows = _cells(csv);
      expect(rows[0], [
        'Last name',
        'First name',
        'Student #',
        'Essay (2026-09-12)',
        'Quiz',
        'Average %',
      ]);
      // (90% of 100 + 40% of 25) / 125 = 100 / 125 = 80.
      expect(rows[1], ['Lovelace', 'Ada', '', '90', '40', '80']);
      // Excused and ungraded work is blank and out of the average.
      expect(rows[2], ['Young', 'Zed', '', '', '', '']);
    });
  });

  group('courseAverage', () {
    test('weights by points possible', () {
      expect(
        courseAverage([
          (percent: 100, pointsPossible: 10),
          (percent: 50, pointsPossible: 30),
        ]),
        closeTo(62.5, 1e-9),
      );
    });

    test('skips ungraded work instead of counting it as zero', () {
      expect(
        courseAverage([
          (percent: 80, pointsPossible: 100),
          (percent: null, pointsPossible: 100),
        ]),
        80,
      );
    });

    test('ignores zero-point assignments and is null when nothing counts', () {
      expect(courseAverage([(percent: 70, pointsPossible: 0)]), isNull);
      expect(courseAverage(const []), isNull);
    });
  });

  test('gradebookOrder: soonest due first, undated last, newest first', () {
    Assignment a(String id, {DateTime? due, int day = 1}) => Assignment(
      id: id,
      courseId: 'c1',
      title: id,
      rubric: essayRubric(),
      dueDate: due,
      createdAt: DateTime(2026, 9, day),
    );
    final ordered = gradebookOrder([
      a('undated-old'),
      a('late', due: DateTime(2026, 10, 5)),
      a('undated-new', day: 9),
      a('soon', due: DateTime(2026, 9, 20)),
    ]);
    expect(ordered.map((x) => x.id), [
      'soon',
      'late',
      'undated-new',
      'undated-old',
    ]);
  });

  test('csvNumber trims trailing zeros and rounds to two places', () {
    expect(csvNumber(82), '82');
    expect(csvNumber(82.5), '82.5');
    expect(csvNumber(66.66666), '66.67');
    expect(csvNumber(null), '');
  });

  test('exportFilename is a dated, filesystem-safe slug', () {
    expect(
      exportFilename(
        ['Essay: Draft #2', 'scores'],
        'csv',
        now: DateTime(2026, 9, 29),
      ),
      'essay-draft-2-scores-2026-09-29.csv',
    );
    expect(
      exportFilename(['Café / Période 3'], 'pdf', now: DateTime(2026, 1, 2)),
      'café-période-3-2026-01-02.pdf',
    );
  });
}
