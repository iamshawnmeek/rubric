import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/home/home_dashboard.dart';

import '../../helpers/fixtures.dart';

/// Wednesday morning.
final _now = DateTime(2026, 9, 30, 10);

final _course = Course(id: 'c1', name: 'English 10', createdAt: t0);

List<Student> _students(int n, {String course = 'c1'}) => [
  for (var i = 0; i < n; i++)
    Student(
      id: '$course-s$i',
      courseId: course,
      firstName: 'S$i',
      lastName: 'L',
    ),
];

Assignment _assignment(
  String id, {
  int? dueInDays,
  bool closed = false,
  String course = 'c1',
}) => Assignment(
  id: id,
  courseId: course,
  title: id,
  rubric: essayRubric(),
  createdAt: t0,
  closed: closed,
  dueDate: dueInDays == null ? null : _now.add(Duration(days: dueInDays)),
);

Evaluation _eval(
  String assignment,
  String student,
  EvaluationStatus status, {
  DateTime? at,
}) => Evaluation(
  id: '$assignment-$student',
  assignmentId: assignment,
  studentId: student,
  status: status,
  updatedAt: at ?? _now,
);

HomeDashboard _compute({
  List<Student>? students,
  List<Assignment> assignments = const [],
  List<Evaluation> evaluations = const [],
  List<Rubric> rubrics = const [],
  List<Course>? courses,
}) => HomeDashboard.compute(
  now: _now,
  courses: courses ?? [_course],
  studentsByCourse: {'c1': students ?? _students(4)},
  assignments: assignments,
  evaluationsByCourse: {'c1': evaluations},
  rubrics: rubrics,
);

void main() {
  group('dayPeriodOf', () {
    test('splits the day at noon and 5pm', () {
      expect(dayPeriodOf(DateTime(2026, 1, 1, 11, 59)), DayPeriod.morning);
      expect(dayPeriodOf(DateTime(2026, 1, 1, 12)), DayPeriod.afternoon);
      expect(dayPeriodOf(DateTime(2026, 1, 1, 16, 59)), DayPeriod.afternoon);
      expect(dayPeriodOf(DateTime(2026, 1, 1, 17)), DayPeriod.evening);
    });
  });

  test('startOfWeek is Monday midnight', () {
    expect(startOfWeek(_now), DateTime(2026, 9, 28));
    expect(startOfWeek(DateTime(2026, 9, 28, 0, 1)), DateTime(2026, 9, 28));
    expect(startOfWeek(DateTime(2026, 10, 4, 23)), DateTime(2026, 9, 28));
  });

  group('to grade', () {
    test('counts complete, excused and missing papers as done', () {
      final d = _compute(
        assignments: [_assignment('a', dueInDays: -1)],
        evaluations: [
          _eval('a', 'c1-s0', EvaluationStatus.complete),
          _eval('a', 'c1-s1', EvaluationStatus.excused),
          _eval('a', 'c1-s2', EvaluationStatus.inProgress),
        ],
      );
      final item = d.toGrade.single;
      expect(item.total, 4);
      expect(item.done, 2);
      expect(item.remaining, 2);
      expect(item.progress, .5);
    });

    test('drops assignments where every paper is resolved', () {
      final d = _compute(
        students: _students(2),
        assignments: [_assignment('a', dueInDays: -1)],
        evaluations: [
          _eval('a', 'c1-s0', EvaluationStatus.complete),
          _eval('a', 'c1-s1', EvaluationStatus.missing),
        ],
      );
      expect(d.toGrade, isEmpty);
    });

    test('ignores closed assignments and papers of removed students', () {
      final d = _compute(
        students: [
          ..._students(1),
          const Student(
            id: 'gone',
            courseId: 'c1',
            firstName: 'Gone',
            lastName: '',
            archived: true,
          ),
        ],
        assignments: [
          _assignment('open', dueInDays: -1),
          _assignment('closed', dueInDays: -1, closed: true),
        ],
        evaluations: [_eval('open', 'gone', EvaluationStatus.complete)],
      );
      expect(d.toGrade.single.assignment.id, 'open');
      expect(d.toGrade.single.total, 1);
      expect(d.toGrade.single.done, 0);
      expect(d.studentCount, 1);
    });

    test('includes work due today, started early, or undated', () {
      final d = _compute(
        assignments: [
          _assignment('today', dueInDays: 0),
          _assignment('started', dueInDays: 4),
          _assignment('undated'),
        ],
        evaluations: [_eval('started', 'c1-s0', EvaluationStatus.inProgress)],
      );
      expect(d.toGrade.map((p) => p.assignment.id), [
        'today',
        'started',
        'undated',
      ]);
      expect(d.comingUp, isEmpty);
    });

    test('sorts oldest due first', () {
      final d = _compute(
        assignments: [
          _assignment('yesterday', dueInDays: -1),
          _assignment('last week', dueInDays: -7),
        ],
      );
      expect(d.toGrade.map((p) => p.assignment.id), ['last week', 'yesterday']);
    });

    test('leaves out archived courses', () {
      final d = _compute(
        assignments: [_assignment('x', dueInDays: -1, course: 'c2')],
      );
      expect(d.toGrade, isEmpty);
    });
  });

  test('coming up holds untouched work due within two weeks', () {
    final d = _compute(
      assignments: [
        _assignment('soon', dueInDays: 5),
        _assignment('sooner', dueInDays: 2),
        _assignment('far', dueInDays: 20),
      ],
    );
    expect(d.comingUp.map((p) => p.assignment.id), ['sooner', 'soon']);
    expect(d.toGrade, isEmpty);
  });

  test('graded this week counts complete papers since Monday', () {
    final d = _compute(
      evaluations: [
        _eval('a', 'c1-s0', EvaluationStatus.complete),
        _eval(
          'a',
          'c1-s1',
          EvaluationStatus.complete,
          at: DateTime(2026, 9, 28),
        ),
        _eval(
          'a',
          'c1-s2',
          EvaluationStatus.complete,
          at: DateTime(2026, 9, 27),
        ),
        _eval('a', 'c1-s3', EvaluationStatus.inProgress),
      ],
    );
    expect(d.gradedThisWeek, 2);
  });

  test('recent rubrics are the three last edited library rubrics', () {
    Rubric r(String id, int day, {bool template = false}) => Rubric(
      id: id,
      title: id,
      createdAt: t0,
      updatedAt: DateTime(2026, 9, day),
      isTemplate: template,
    );
    final d = _compute(
      rubrics: [
        r('a', 1),
        r('b', 5),
        r('t', 9, template: true),
        r('c', 3),
        r('d', 4),
      ],
    );
    expect(d.recentRubrics.map((r) => r.id), ['b', 'd', 'c']);
  });

  test('is empty only with no classes and no rubrics', () {
    expect(_compute(courses: []).isEmpty, isTrue);
    expect(_compute().isEmpty, isFalse);
    expect(
      _compute(
        courses: [],
        rubrics: [Rubric(id: 'r', title: 'R', createdAt: t0, updatedAt: t0)],
      ).isEmpty,
      isFalse,
    );
  });
}
