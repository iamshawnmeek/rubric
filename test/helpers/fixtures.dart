import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';

final t0 = DateTime(2026, 9, 1, 12);

/// Writing (60%): grammar, organization. Research (40%): sources.
Rubric essayRubric({GradingMode mode = GradingMode.simple}) => Rubric(
  id: 'r1',
  title: 'Essay',
  mode: mode,
  createdAt: t0,
  updatedAt: t0,
  levels: const [
    PerformanceLevel(id: 'L4', label: 'Exemplary', points: 4),
    PerformanceLevel(id: 'L3', label: 'Proficient', points: 3),
    PerformanceLevel(id: 'L2', label: 'Developing', points: 2),
    PerformanceLevel(id: 'L1', label: 'Beginning', points: 1),
  ],
  groups: const [
    RubricGroup(
      id: 'g1',
      title: 'Writing',
      weight: 60,
      objectives: [
        Objective(id: 'o1', title: 'Grammar', descriptors: {'L4': 'Flawless'}),
        Objective(id: 'o2', title: 'Organization'),
      ],
    ),
    RubricGroup(
      id: 'g2',
      title: 'Research',
      weight: 40,
      objectives: [Objective(id: 'o3', title: 'Sources')],
    ),
  ],
);

Evaluation eval(
  Map<String, ObjectiveScore> scores, {
  String student = 's1',
  EvaluationStatus status = EvaluationStatus.inProgress,
  double penalty = 0,
  double? override,
}) => Evaluation(
  id: 'e-$student',
  assignmentId: 'a1',
  studentId: student,
  status: status,
  scores: scores,
  penaltyPercent: penalty,
  overridePercent: override,
  updatedAt: t0,
);
