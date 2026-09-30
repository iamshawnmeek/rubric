import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rubric/domain/ids.dart';

/// A mark on one objective: a percentage (simple rubrics) or a performance
/// level (detailed rubrics).
@immutable
sealed class ObjectiveScore {
  const new();

  factory fromJson(Map<String, dynamic> json) => switch (json['type']) {
    'percent' => PercentScore((json['value'] as num).toDouble()),
    'level' => LevelScore(json['levelId'] as String),
    final other => throw FormatException('Unknown score type $other'),
  };

  Map<String, dynamic> toJson();
}

@immutable
final class PercentScore extends ObjectiveScore {
  const new(this.value);

  /// 0–100.
  final double value;

  @override
  Map<String, dynamic> toJson() => {'type': 'percent', 'value': value};

  @override
  bool operator ==(Object other) =>
      other is PercentScore && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@immutable
final class LevelScore extends ObjectiveScore {
  const new(this.levelId);

  final String levelId;

  @override
  Map<String, dynamic> toJson() => {'type': 'level', 'levelId': levelId};

  @override
  bool operator ==(Object other) =>
      other is LevelScore && other.levelId == levelId;

  @override
  int get hashCode => levelId.hashCode;
}

enum EvaluationStatus {
  notStarted,
  inProgress,
  complete,

  /// Not counted in averages; no grade is shown.
  excused,

  /// Work not handed in. Counts as zero unless a score is entered.
  missing,
}

/// One student's marks on one assignment.
@immutable
class Evaluation {
  const new({
    required this.id,
    required this.assignmentId,
    required this.studentId,
    required this.updatedAt,
    this.status = EvaluationStatus.notStarted,
    this.scores = const {},
    this.objectiveComments = const {},
    this.comment = '',
    this.late = false,
    this.penaltyPercent = 0,
    this.overridePercent,
    this.overrideReason = '',
  });

  factory fromJson(Map<String, dynamic> json) => Evaluation(
    id: json['id'] as String,
    assignmentId: json['assignmentId'] as String,
    studentId: json['studentId'] as String,
    status: EvaluationStatus.values.byName(json['status'] as String),
    scores: (json['scores'] as Map<String, dynamic>? ?? const {}).map(
      (k, v) => MapEntry(k, ObjectiveScore.fromJson(v as Map<String, dynamic>)),
    ),
    objectiveComments:
        (json['objectiveComments'] as Map<String, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(k, v as String),
        ),
    comment: json['comment'] as String? ?? '',
    late: json['late'] as bool? ?? false,
    penaltyPercent: (json['penaltyPercent'] as num?)?.toDouble() ?? 0,
    overridePercent: (json['overridePercent'] as num?)?.toDouble(),
    overrideReason: json['overrideReason'] as String? ?? '',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
  );

  /// A fresh paper for [studentId] on [assignmentId].
  ///
  /// The id is DERIVED from the pair, not random: two devices that each start
  /// grading the same student offline create the same row, which sync merges,
  /// instead of two rows for one paper that the server has no way to join.
  factory start({
    required String assignmentId,
    required String studentId,
    DateTime? now,
  }) => Evaluation(
    id: idFor(assignmentId, studentId),
    assignmentId: assignmentId,
    studentId: studentId,
    updatedAt: now ?? DateTime.now(),
  );

  static String idFor(String assignmentId, String studentId) =>
      '${assignmentId}_$studentId';

  final String id;
  final String assignmentId;
  final String studentId;
  final EvaluationStatus status;

  /// Keyed by objective id.
  final Map<String, ObjectiveScore> scores;

  /// Feedback on individual objectives, keyed by objective id.
  final Map<String, String> objectiveComments;

  /// Overall feedback.
  final String comment;
  final bool late;

  /// Percentage points deducted from the computed grade (e.g. late work).
  final double penaltyPercent;

  /// When set, replaces the computed percentage entirely.
  final double? overridePercent;

  /// Why the teacher overrode the computed grade.
  final String overrideReason;
  final DateTime updatedAt;

  Evaluation copyWith({
    EvaluationStatus? status,
    Map<String, ObjectiveScore>? scores,
    Map<String, String>? objectiveComments,
    String? comment,
    bool? late,
    double? penaltyPercent,
    double? overridePercent,
    String? overrideReason,
    bool clearOverride = false,
    DateTime? updatedAt,
  }) => Evaluation(
    id: id,
    assignmentId: assignmentId,
    studentId: studentId,
    status: status ?? this.status,
    scores: scores ?? this.scores,
    objectiveComments: objectiveComments ?? this.objectiveComments,
    comment: comment ?? this.comment,
    late: late ?? this.late,
    penaltyPercent: penaltyPercent ?? this.penaltyPercent,
    overridePercent: clearOverride
        ? null
        : overridePercent ?? this.overridePercent,
    overrideReason: clearOverride ? '' : overrideReason ?? this.overrideReason,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  /// Returns a copy with [score] set (or cleared when null) for [objectiveId].
  Evaluation withScore(String objectiveId, ObjectiveScore? score) {
    final next = Map<String, ObjectiveScore>.of(scores);
    if (score == null) {
      next.remove(objectiveId);
    } else {
      next[objectiveId] = score;
    }
    return copyWith(scores: next);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'assignmentId': assignmentId,
    'studentId': studentId,
    'status': status.name,
    'scores': scores.map((k, v) => MapEntry(k, v.toJson())),
    'objectiveComments': objectiveComments,
    'comment': comment,
    'late': late,
    'penaltyPercent': penaltyPercent,
    'overridePercent': overridePercent,
    'overrideReason': overrideReason,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is Evaluation &&
      other.id == id &&
      other.assignmentId == assignmentId &&
      other.studentId == studentId &&
      other.status == status &&
      const MapEquality<String, ObjectiveScore>().equals(
        other.scores,
        scores,
      ) &&
      const MapEquality<String, String>().equals(
        other.objectiveComments,
        objectiveComments,
      ) &&
      other.comment == comment &&
      other.late == late &&
      other.penaltyPercent == penaltyPercent &&
      other.overridePercent == overridePercent &&
      other.overrideReason == overrideReason &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, status, updatedAt, scores.length);
}

/// A reusable piece of feedback in the teacher's comment bank.
@immutable
class CommentSnippet {
  const new({
    required this.id,
    required this.text,
    this.category = '',
    this.useCount = 0,
  });

  factory create(String text, {String category = ''}) =>
      CommentSnippet(id: newId(), text: text, category: category);

  final String id;
  final String text;
  final String category;
  final int useCount;

  CommentSnippet copyWith({String? text, String? category, int? useCount}) =>
      CommentSnippet(
        id: id,
        text: text ?? this.text,
        category: category ?? this.category,
        useCount: useCount ?? this.useCount,
      );

  @override
  bool operator ==(Object other) =>
      other is CommentSnippet &&
      other.id == id &&
      other.text == text &&
      other.category == category &&
      other.useCount == useCount;

  @override
  int get hashCode => Object.hash(id, text, category, useCount);
}
