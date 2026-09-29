import 'dart:math';

import 'package:rubric/data/assignment_repository.dart';
import 'package:rubric/data/comment_repository.dart';
import 'package:rubric/data/course_repository.dart';
import 'package:rubric/data/database.dart';
import 'package:rubric/data/rubric_repository.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';

/// Every id the demo creates starts with this, so the data is recognisable and
/// re-running the loader finds what it already wrote.
const sampleIdPrefix = 'sample-';

/// Loads a realistic demo classroom (courses, students, rubrics, assignments,
/// graded work, comment bank). Idempotent: calling it twice adds nothing new.
///
/// Every id is fixed and the random numbers come from a seeded [Random], so
/// the same demo appears on every device; only due dates and grading times
/// move with [now] (default: today), so the demo always looks current.
///
/// An entity that already exists is left alone — a teacher who edited or
/// graded sample work does not have it reset by loading the demo again.
Future<void> loadSampleData(AppDatabase db, {DateTime? now}) async {
  final today = now ?? DateTime.now();
  final rubrics = RubricRepository(db);
  final courses = CourseRepository(db);
  final assignments = AssignmentRepository(db);
  final comments = CommentRepository(db);
  final random = Random(20260929);

  await db.transaction(() async {
    final library = _rubrics(today);
    for (final rubric in library) {
      if (await rubrics.get(rubric.id) == null) {
        await rubrics.save(rubric, now: rubric.updatedAt);
      }
    }

    final names = _studentNames(random);
    for (final (courseIndex, plan) in _courses.indexed) {
      final course = Course(
        id: '${sampleIdPrefix}course-${plan.key}',
        name: plan.name,
        section: plan.section,
        term: 'Fall 2026',
        createdAt: today.subtract(const Duration(days: 40)),
      );
      if (await courses.getCourse(course.id) == null) {
        await courses.saveCourse(course);
      }

      final roster = [
        for (var i = 0; i < _studentsPerCourse; i++)
          Student(
            id: '${sampleIdPrefix}student-${plan.key}-${i + 1}',
            courseId: course.id,
            firstName: names[courseIndex * _studentsPerCourse + i].$1,
            lastName: names[courseIndex * _studentsPerCourse + i].$2,
            studentNumber:
                '${2610 + courseIndex}${(i + 1).toString().padLeft(3, '0')}',
          ),
      ];
      final existingStudents = {
        for (final s in await courses.students(
          course.id,
          includeArchived: true,
        ))
          s.id,
      };
      await courses.saveStudents(
        roster.where((s) => !existingStudents.contains(s.id)),
      );

      // How strong each student is, so one student's marks hang together
      // across assignments instead of being noise.
      final ability = [for (final _ in roster) 58 + random.nextInt(40)];

      for (final work in plan.assignments) {
        final rubric = library.firstWhere((r) => r.id == work.rubricId);
        final assignment = Assignment(
          id: '${sampleIdPrefix}assignment-${work.key}',
          courseId: course.id,
          title: work.title,
          description: work.description,
          rubric: rubric,
          sourceRubricId: rubric.id,
          dueDate: _dueDate(today, work.dueInDays),
          createdAt: today.subtract(Duration(days: 14 - work.dueInDays)),
        );
        if (await assignments.get(assignment.id) == null) {
          await assignments.save(assignment);
        }

        final existing = {
          for (final e in await assignments.evaluations(assignment.id))
            e.studentId,
        };
        final evaluations = [
          for (final (i, student) in roster.indexed)
            ?_evaluation(
              random: random,
              today: today,
              rubric: rubric,
              assignmentId: assignment.id,
              student: student,
              index: i,
              ability: ability[i],
              stage: work.stage,
            ),
        ];
        await assignments.saveEvaluations(
          evaluations.where((e) => !existing.contains(e.studentId)),
        );
      }
    }

    final existingSnippets = {for (final s in await comments.all()) s.id};
    for (final (i, (category, text)) in _snippets.indexed) {
      final id = '${sampleIdPrefix}comment-${i + 1}';
      if (existingSnippets.contains(id)) continue;
      await comments.save(
        CommentSnippet(
          id: id,
          text: text,
          category: category,
          useCount: random.nextInt(12),
        ),
      );
    }
  });
}

const _studentsPerCourse = 24;

/// How far grading has got on a demo assignment.
enum _Stage {
  /// Handed back: nearly everyone complete, a couple missing, one excused.
  graded,

  /// Mid-stack: some complete, a few half-marked, the rest untouched.
  grading,

  /// Not due yet; nothing handed in.
  upcoming,
}

typedef _AssignmentPlan = ({
  String key,
  String title,
  String description,
  String rubricId,
  int dueInDays,
  _Stage stage,
});

typedef _CoursePlan = ({
  String key,
  String name,
  String section,
  List<_AssignmentPlan> assignments,
});

const _essayId = '${sampleIdPrefix}rubric-essay';
const _labId = '${sampleIdPrefix}rubric-lab';
const _talkId = '${sampleIdPrefix}rubric-presentation';

const List<_CoursePlan> _courses = [
  (
    key: 'english10',
    name: 'English 10',
    section: 'Period 2',
    assignments: [
      (
        key: 'uniforms-essay',
        title: 'Persuasive Essay: School Uniforms',
        description: 'Take a position and defend it with at least two sources.',
        rubricId: _essayId,
        dueInDays: -9,
        stage: _Stage.graded,
      ),
      (
        key: 'book-talk',
        title: 'Book Talk: Of Mice and Men',
        description: 'A four-minute talk on a theme of your choice.',
        rubricId: _talkId,
        dueInDays: -2,
        stage: _Stage.grading,
      ),
      (
        key: 'literary-analysis',
        title: 'Literary Analysis Essay',
        description: 'How does Steinbeck use setting to foreshadow the ending?',
        rubricId: _essayId,
        dueInDays: 5,
        stage: _Stage.upcoming,
      ),
    ],
  ),
  (
    key: 'biology',
    name: 'Biology',
    section: 'Period 5',
    assignments: [
      (
        key: 'enzyme-lab',
        title: 'Enzyme Activity Lab',
        description: 'Catalase and hydrogen peroxide at five temperatures.',
        rubricId: _labId,
        dueInDays: -6,
        stage: _Stage.graded,
      ),
      (
        key: 'cell-presentation',
        title: 'Cell Structure Presentation',
        description: 'Pairs present one organelle and its job.',
        rubricId: _talkId,
        dueInDays: -1,
        stage: _Stage.grading,
      ),
      (
        key: 'photosynthesis-lab',
        title: 'Photosynthesis Lab',
        description: 'Leaf disks and light intensity.',
        rubricId: _labId,
        dueInDays: 3,
        stage: _Stage.upcoming,
      ),
    ],
  ),
];

/// Due at 8am [days] from [today], the way a school deadline reads.
DateTime _dueDate(DateTime today, int days) =>
    DateTime(today.year, today.month, today.day + days, 8);

Evaluation? _evaluation({
  required Random random,
  required DateTime today,
  required Rubric rubric,
  required String assignmentId,
  required Student student,
  required int index,
  required int ability,
  required _Stage stage,
}) {
  if (stage == _Stage.upcoming) return null;

  final status = switch (stage) {
    _Stage.graded when index == 4 => EvaluationStatus.excused,
    _Stage.graded when index == 9 || index == 17 => EvaluationStatus.missing,
    _Stage.graded => EvaluationStatus.complete,
    _Stage.grading when index < 9 => EvaluationStatus.complete,
    _Stage.grading when index < 12 => EvaluationStatus.inProgress,
    _Stage.grading when index == 20 => EvaluationStatus.missing,
    _Stage.grading => EvaluationStatus.notStarted,
    _Stage.upcoming => throw StateError('unreachable'),
  };

  final objectives = rubric.objectives;
  final scoredCount = switch (status) {
    EvaluationStatus.complete => objectives.length,
    EvaluationStatus.inProgress => 1 + random.nextInt(objectives.length - 1),
    _ => 0,
  };

  final scores = <String, ObjectiveScore>{};
  for (final objective in objectives.take(scoredCount)) {
    final percent = (ability + random.nextInt(21) - 12).clamp(35, 100);
    scores[objective.id] = rubric.mode == GradingMode.detailed
        ? LevelScore(_levelFor(rubric, percent))
        : PercentScore((percent / 5).round() * 5.0);
  }

  final late = status == EvaluationStatus.complete && index % 11 == 7;
  final hoursAgo = switch (stage) {
    _Stage.graded => 30 + random.nextInt(96),
    _ => 1 + random.nextInt(40),
  };

  return Evaluation(
    id: '$assignmentId-evaluation-${index + 1}',
    assignmentId: assignmentId,
    studentId: student.id,
    status: status,
    scores: scores,
    comment: status == EvaluationStatus.complete
        ? _overallComment(student.firstName, ability, random)
        : '',
    late: late,
    penaltyPercent: late ? 10 : 0,
    updatedAt: today.subtract(Duration(hours: hoursAgo)),
  );
}

String _levelFor(Rubric rubric, int percent) {
  final index = switch (percent) {
    >= 88 => 0,
    >= 74 => 1,
    >= 60 => 2,
    _ => 3,
  };
  return rubric.levels[index].id;
}

String _overallComment(String name, int ability, Random random) {
  final options = switch (ability) {
    >= 88 => [
      'Excellent work, $name — clear, confident and well supported.',
      'Outstanding, $name. This is a model for the class.',
      'Really polished work. Keep pushing yourself, $name!',
    ],
    >= 74 => [
      'Solid work, $name. Tighten your evidence and this becomes great.',
      'Good job overall — see my notes on organization.',
      'Nice progress, $name. Watch the details in your conclusion.',
    ],
    _ => [
      "Let's talk during office hours, $name — I know you can do more.",
      'A start, but several parts are incomplete. Please see me.',
      'Review the rubric before your revision, $name. You can raise this.',
    ],
  };
  return options[random.nextInt(options.length)];
}

// ---- Library rubrics -------------------------------------------------------

List<Rubric> _rubrics(DateTime today) {
  PerformanceLevel level(String key, String label, double points) =>
      PerformanceLevel(
        id: '${sampleIdPrefix}level-$key',
        label: label,
        points: points,
      );
  Objective objective(
    String key,
    String title, [
    String description = '',
    Map<String, String> descriptors = const {},
  ]) => Objective(
    id: '${sampleIdPrefix}objective-$key',
    title: title,
    description: description,
    descriptors: {
      for (final e in descriptors.entries)
        '${sampleIdPrefix}level-${e.key}': e.value,
    },
  );
  RubricGroup group(
    String key,
    String title,
    int weight,
    List<Objective> objectives,
  ) => RubricGroup(
    id: '${sampleIdPrefix}group-$key',
    title: title,
    weight: weight,
    objectives: objectives,
  );
  DateTime daysAgo(int days) => today.subtract(Duration(days: days));

  return [
    Rubric(
      id: _essayId,
      title: 'Argumentative Essay',
      subject: 'English',
      description: 'For persuasive and analytical essays, grades 9–12.',
      levels: [
        level('essay-4', 'Exemplary', 4),
        level('essay-3', 'Proficient', 3),
        level('essay-2', 'Developing', 2),
        level('essay-1', 'Beginning', 1),
      ],
      groups: [
        group('essay-argument', 'Argument', 40, [
          objective(
            'essay-thesis',
            'Thesis and claim',
            'A clear, arguable position stated early.',
          ),
          objective(
            'essay-evidence',
            'Evidence and reasoning',
            'Relevant quotations and data, explained rather than dropped in.',
          ),
        ]),
        group('essay-organization', 'Organization', 30, [
          objective(
            'essay-structure',
            'Structure and transitions',
            'Paragraphs build on each other; transitions show the logic.',
          ),
        ]),
        group('essay-conventions', 'Conventions', 30, [
          objective('essay-grammar', 'Grammar, usage and mechanics'),
          objective(
            'essay-citations',
            'Citations',
            'MLA 9 in-text and works cited.',
          ),
        ]),
      ],
      createdAt: daysAgo(60),
      updatedAt: daysAgo(12),
    ),
    Rubric(
      id: _labId,
      title: 'Lab Report',
      subject: 'Science',
      description: 'Four-level analytic rubric for formal lab write-ups.',
      mode: GradingMode.detailed,
      levels: [
        level('lab-4', 'Exemplary', 4),
        level('lab-3', 'Proficient', 3),
        level('lab-2', 'Developing', 2),
        level('lab-1', 'Beginning', 1),
      ],
      groups: [
        group('lab-question', 'Question and hypothesis', 20, [
          objective('lab-hypothesis', 'Testable hypothesis', '', {
            'lab-4': 'Specific, testable and tied to the underlying science.',
            'lab-3': 'Testable and clearly stated.',
            'lab-2': 'Stated but vague or hard to test.',
            'lab-1': 'Missing or not a hypothesis.',
          }),
        ]),
        group('lab-method', 'Method and data', 40, [
          objective('lab-procedure', 'Procedure', '', {
            'lab-4': 'Another student could repeat it exactly.',
            'lab-3': 'Complete, with minor gaps.',
            'lab-2': 'Several steps unclear or missing.',
            'lab-1': 'Could not be followed.',
          }),
          objective('lab-data', 'Data tables and graphs', '', {
            'lab-4': 'Labelled, with units, and the right graph type.',
            'lab-3': 'Mostly labelled; small errors.',
            'lab-2': 'Data present but hard to read.',
            'lab-1': 'Data missing or unusable.',
          }),
        ]),
        group('lab-analysis', 'Analysis', 40, [
          objective('lab-interpretation', 'Interpretation of results', '', {
            'lab-4': 'Explains trends with evidence and science concepts.',
            'lab-3': 'Describes trends accurately.',
            'lab-2': 'Restates data without explaining it.',
            'lab-1': 'Missing or inaccurate.',
          }),
          objective('lab-error', 'Sources of error and conclusion', '', {
            'lab-4': 'Specific errors and their effect on the result.',
            'lab-3': 'Names plausible errors.',
            'lab-2': 'Generic ("human error").',
            'lab-1': 'Missing.',
          }),
        ]),
      ],
      createdAt: daysAgo(45),
      updatedAt: daysAgo(3),
    ),
    Rubric(
      id: _talkId,
      title: 'Oral Presentation',
      subject: 'Speaking and listening',
      description: 'Short talks, book talks and project presentations.',
      levels: [
        level('talk-4', 'Exemplary', 4),
        level('talk-3', 'Proficient', 3),
        level('talk-2', 'Developing', 2),
        level('talk-1', 'Beginning', 1),
      ],
      groups: [
        group('talk-content', 'Content', 50, [
          objective('talk-accuracy', 'Accuracy'),
          objective('talk-depth', 'Depth of insight'),
        ]),
        group('talk-delivery', 'Delivery', 30, [
          objective('talk-voice', 'Voice and pacing'),
          objective('talk-eye', 'Eye contact and presence'),
        ]),
        group('talk-visuals', 'Visual aids', 20, [
          objective('talk-slides', 'Slides support the talk'),
        ]),
      ],
      createdAt: daysAgo(30),
      updatedAt: daysAgo(1),
    ),
  ];
}

// ---- People and comments ---------------------------------------------------

const _firstNames = [
  'Aaliyah',
  'Mateo',
  'Priya',
  'Jamal',
  'Sofia',
  'Wei',
  'Amara',
  'Liam',
  'Fatima',
  'Diego',
  'Hana',
  'Elijah',
  'Zoe',
  'Kenji',
  'Imani',
  'Lucas',
  'Nadia',
  'Tariq',
  'Isabella',
  'Oluwaseun',
  'Maya',
  'Arjun',
  'Chloe',
  'Malik',
  'Leilani',
  'Santiago',
  'Grace',
  'Yusuf',
  'Emma',
  'Dmitri',
  'Ava',
  'Kofi',
  'Mei',
  'Noah',
  'Esperanza',
  'Rohan',
  'Layla',
  'Caleb',
  'Aisha',
  'Finn',
  'Valentina',
  'Hiroshi',
  'Naomi',
  'Ezra',
  'Camila',
  'Jin',
  'Riley',
  'Tomás',
];

const _lastNames = [
  'Johnson',
  'Hernández',
  'Patel',
  'Washington',
  'Rossi',
  'Zhang',
  'Okafor',
  "O'Brien",
  'Rahman',
  'García',
  'Kim',
  'Brooks',
  'Nguyen',
  'Tanaka',
  'Mensah',
  'Silva',
  'Haddad',
  'Ali',
  'Morales',
  'Adeyemi',
  'Cohen',
  'Sharma',
  'Dubois',
  'Jackson',
  'Kahale',
  'Ramírez',
  'Park',
  'Yilmaz',
  'Schmidt',
  'Petrov',
  'Martin',
  'Owusu',
  'Chen',
  'Williams',
  'Castillo',
  'Gupta',
  'Nasser',
  'Thompson',
  'Abdi',
  'Murphy',
  'López',
  'Sato',
  'Levi',
  'Fischer',
  'Reyes',
  'Choi',
  'Bennett',
  'Alvarez',
];

/// 48 distinct first/last pairings, shuffled deterministically.
List<(String, String)> _studentNames(Random random) {
  final first = [..._firstNames]..shuffle(random);
  final last = [..._lastNames]..shuffle(random);
  return [for (var i = 0; i < first.length; i++) (first[i], last[i])];
}

const _snippets = [
  ('Praise', 'Your thesis is clear and arguable — great start.'),
  ('Praise', 'Excellent use of evidence to support your claim.'),
  ('Praise', 'Your data tables are clean and easy to read.'),
  ('Praise', 'Confident delivery and great eye contact.'),
  ('Evidence', 'Explain how this quotation supports your point.'),
  ('Evidence', 'Add a second source to strengthen this argument.'),
  ('Evidence', 'Cite the page number for direct quotations.'),
  ('Organization', 'Use a transition to connect these two paragraphs.'),
  ('Organization', 'Your conclusion restates the intro — push it further.'),
  ('Conventions', 'Watch for comma splices; read your sentences aloud.'),
  ('Conventions', 'Check subject–verb agreement in this paragraph.'),
  ('Science', 'Label both axes and include units.'),
  ('Science', 'Name a specific source of error and how it affected results.'),
  ('Next steps', 'Please see me during office hours to plan your revision.'),
  ('Next steps', 'Revise and resubmit by Friday for up to full credit.'),
];
