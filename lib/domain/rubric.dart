import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/ids.dart';

/// How each objective is scored.
enum GradingMode {
  /// Each objective gets a 0–100 percentage.
  simple,

  /// Each objective is placed on a ladder of [PerformanceLevel]s.
  detailed,
}

/// One rung on a detailed rubric's ladder (e.g. "Proficient", 3 points).
@immutable
class PerformanceLevel {
  const new({required this.id, required this.label, required this.points});

  factory fromJson(Map<String, dynamic> json) => PerformanceLevel(
    id: json['id'] as String,
    label: json['label'] as String,
    points: (json['points'] as num).toDouble(),
  );

  final String id;
  final String label;
  final double points;

  PerformanceLevel copyWith({String? label, double? points}) =>
      PerformanceLevel(
        id: id,
        label: label ?? this.label,
        points: points ?? this.points,
      );

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'points': points};

  @override
  bool operator ==(Object other) =>
      other is PerformanceLevel &&
      other.id == id &&
      other.label == label &&
      other.points == points;

  @override
  int get hashCode => Object.hash(id, label, points);

  /// The four-level ladder most teachers start from.
  static List<PerformanceLevel> defaults() => [
    PerformanceLevel(id: newId(), label: 'Exemplary', points: 4),
    PerformanceLevel(id: newId(), label: 'Proficient', points: 3),
    PerformanceLevel(id: newId(), label: 'Developing', points: 2),
    PerformanceLevel(id: newId(), label: 'Beginning', points: 1),
  ];
}

/// A single thing being graded ("Grammar, usage and mechanics").
@immutable
class Objective {
  const new({
    required this.id,
    required this.title,
    this.description = '',
    this.descriptors = const {},
  });

  factory create(String title) => Objective(id: newId(), title: title);

  factory fromJson(Map<String, dynamic> json) => Objective(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    descriptors: (json['descriptors'] as Map<String, dynamic>? ?? const {}).map(
      (k, v) => MapEntry(k, v as String),
    ),
  );

  final String id;
  final String title;
  final String description;

  /// What performance at each level looks like, keyed by [PerformanceLevel.id].
  final Map<String, String> descriptors;

  Objective copyWith({
    String? title,
    String? description,
    Map<String, String>? descriptors,
  }) => Objective(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    descriptors: descriptors ?? this.descriptors,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'descriptors': descriptors,
  };

  @override
  bool operator ==(Object other) =>
      other is Objective &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      const MapEquality<String, String>().equals(
        other.descriptors,
        descriptors,
      );

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    const MapEquality<String, String>().hash(descriptors),
  );
}

/// A weighted bucket of objectives. Weights across a rubric sum to 100.
@immutable
class RubricGroup {
  const new({
    required this.id,
    required this.title,
    required this.weight,
    this.objectives = const [],
  });

  factory create(String title, {int weight = 0}) =>
      RubricGroup(id: newId(), title: title, weight: weight);

  factory fromJson(Map<String, dynamic> json) => RubricGroup(
    id: json['id'] as String,
    title: json['title'] as String,
    weight: (json['weight'] as num).round(),
    objectives: (json['objectives'] as List<dynamic>)
        .map((e) => Objective.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String title;

  /// Whole-number percentage of the final grade.
  final int weight;
  final List<Objective> objectives;

  RubricGroup copyWith({
    String? title,
    int? weight,
    List<Objective>? objectives,
  }) => RubricGroup(
    id: id,
    title: title ?? this.title,
    weight: weight ?? this.weight,
    objectives: objectives ?? this.objectives,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'weight': weight,
    'objectives': objectives.map((o) => o.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is RubricGroup &&
      other.id == id &&
      other.title == title &&
      other.weight == weight &&
      const ListEquality<Objective>().equals(other.objectives, objectives);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    weight,
    const ListEquality<Objective>().hash(objectives),
  );
}

/// Problems that stop a rubric from being used to grade.
enum RubricIssue {
  noTitle,
  noGroups,
  emptyGroup,
  weightsNotHundred,
  noLevels,
  duplicateLevelPoints,
}

@immutable
class Rubric {
  const new({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.subject = '',
    this.mode = GradingMode.simple,
    this.levels = const [],
    this.groups = const [],
    this.scale = GradingScale.standard,
    this.isTemplate = false,
    this.archived = false,
  });

  factory create({String title = '', DateTime? now}) {
    final at = now ?? DateTime.now();
    return Rubric(
      id: newId(),
      title: title,
      createdAt: at,
      updatedAt: at,
      levels: PerformanceLevel.defaults(),
    );
  }

  factory fromJson(Map<String, dynamic> json) => Rubric(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    subject: json['subject'] as String? ?? '',
    mode: GradingMode.values.byName(json['mode'] as String? ?? 'simple'),
    levels: (json['levels'] as List<dynamic>? ?? const [])
        .map((e) => PerformanceLevel.fromJson(e as Map<String, dynamic>))
        .toList(),
    groups: (json['groups'] as List<dynamic>? ?? const [])
        .map((e) => RubricGroup.fromJson(e as Map<String, dynamic>))
        .toList(),
    scale: json['scale'] == null
        ? GradingScale.standard
        : GradingScale.fromJson(json['scale'] as Map<String, dynamic>),
    isTemplate: json['isTemplate'] as bool? ?? false,
    archived: json['archived'] as bool? ?? false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
  );

  final String id;
  final String title;
  final String description;
  final String subject;
  final GradingMode mode;

  /// Ordered best → worst. Only meaningful in [GradingMode.detailed].
  final List<PerformanceLevel> levels;
  final List<RubricGroup> groups;
  final GradingScale scale;
  final bool isTemplate;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<Objective> get objectives =>
      groups.expand((g) => g.objectives).toList(growable: false);

  int get totalWeight => groups.fold(0, (sum, g) => sum + g.weight);

  double get maxLevelPoints =>
      levels.isEmpty ? 0 : levels.map((l) => l.points).max;

  PerformanceLevel? levelById(String id) =>
      levels.firstWhereOrNull((l) => l.id == id);

  RubricGroup? groupOf(String objectiveId) => groups.firstWhereOrNull(
    (g) => g.objectives.any((o) => o.id == objectiveId),
  );

  List<RubricIssue> get issues => [
    if (title.trim().isEmpty) RubricIssue.noTitle,
    if (groups.isEmpty) RubricIssue.noGroups,
    if (groups.any((g) => g.objectives.isEmpty)) RubricIssue.emptyGroup,
    if (groups.isNotEmpty && totalWeight != 100) RubricIssue.weightsNotHundred,
    if (mode == GradingMode.detailed && levels.isEmpty) RubricIssue.noLevels,
    if (mode == GradingMode.detailed &&
        levels.map((l) => l.points).toSet().length != levels.length)
      RubricIssue.duplicateLevelPoints,
  ];

  bool get isReady => issues.isEmpty;

  Rubric copyWith({
    String? id,
    String? title,
    String? description,
    String? subject,
    GradingMode? mode,
    List<PerformanceLevel>? levels,
    List<RubricGroup>? groups,
    GradingScale? scale,
    bool? isTemplate,
    bool? archived,
    DateTime? updatedAt,
  }) => Rubric(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    subject: subject ?? this.subject,
    mode: mode ?? this.mode,
    levels: levels ?? this.levels,
    groups: groups ?? this.groups,
    scale: scale ?? this.scale,
    isTemplate: isTemplate ?? this.isTemplate,
    archived: archived ?? this.archived,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// A deep copy with fresh ids everywhere (used for "duplicate" and for
  /// instantiating templates). Level ids inside descriptors are remapped.
  Rubric duplicate({String? title, bool? isTemplate, DateTime? now}) {
    final at = now ?? DateTime.now();
    final levelIds = {for (final l in levels) l.id: newId()};
    return Rubric(
      id: newId(),
      title: title ?? this.title,
      description: description,
      subject: subject,
      mode: mode,
      levels: [
        for (final l in levels)
          PerformanceLevel(
            id: levelIds[l.id]!,
            label: l.label,
            points: l.points,
          ),
      ],
      groups: [
        for (final g in groups)
          RubricGroup(
            id: newId(),
            title: g.title,
            weight: g.weight,
            objectives: [
              for (final o in g.objectives)
                Objective(
                  id: newId(),
                  title: o.title,
                  description: o.description,
                  descriptors: {
                    for (final e in o.descriptors.entries)
                      if (levelIds[e.key] != null) levelIds[e.key]!: e.value,
                  },
                ),
            ],
          ),
      ],
      scale: scale,
      isTemplate: isTemplate ?? this.isTemplate,
      createdAt: at,
      updatedAt: at,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'subject': subject,
    'mode': mode.name,
    'levels': levels.map((l) => l.toJson()).toList(),
    'groups': groups.map((g) => g.toJson()).toList(),
    'scale': scale.toJson(),
    'isTemplate': isTemplate,
    'archived': archived,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is Rubric &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.subject == subject &&
      other.mode == mode &&
      const ListEquality<PerformanceLevel>().equals(other.levels, levels) &&
      const ListEquality<RubricGroup>().equals(other.groups, groups) &&
      other.scale == scale &&
      other.isTemplate == isTemplate &&
      other.archived == archived &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, title, mode, updatedAt, groups.length);
}
