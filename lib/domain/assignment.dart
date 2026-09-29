import 'package:meta/meta.dart';
import 'package:rubric/domain/ids.dart';
import 'package:rubric/domain/rubric.dart';

/// A piece of work in a course, graded against a SNAPSHOT of a rubric.
///
/// The snapshot is deliberate: editing a rubric in the library later must not
/// silently re-grade work that was already marked against the old version.
@immutable
class Assignment {
  const new({
    required this.id,
    required this.courseId,
    required this.title,
    required this.rubric,
    required this.createdAt,
    this.sourceRubricId,
    this.description = '',
    this.dueDate,
    this.pointsPossible = 100,
    this.closed = false,
  });

  factory create({
    required String courseId,
    required String title,
    required Rubric rubric,
    DateTime? dueDate,
    String description = '',
    double pointsPossible = 100,
    DateTime? now,
  }) => Assignment(
    id: newId(),
    courseId: courseId,
    title: title,
    rubric: rubric,
    sourceRubricId: rubric.id,
    dueDate: dueDate,
    description: description,
    pointsPossible: pointsPossible,
    createdAt: now ?? DateTime.now(),
  );

  final String id;
  final String courseId;
  final String title;
  final String description;
  final Rubric rubric;

  /// The library rubric this was created from, if it still exists.
  final String? sourceRubricId;
  final DateTime? dueDate;

  /// What 100% is worth when exporting points to a gradebook/LMS.
  final double pointsPossible;
  final bool closed;
  final DateTime createdAt;

  Assignment copyWith({
    String? title,
    String? description,
    Rubric? rubric,
    DateTime? dueDate,
    bool clearDueDate = false,
    double? pointsPossible,
    bool? closed,
  }) => Assignment(
    id: id,
    courseId: courseId,
    title: title ?? this.title,
    description: description ?? this.description,
    rubric: rubric ?? this.rubric,
    sourceRubricId: sourceRubricId,
    dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
    pointsPossible: pointsPossible ?? this.pointsPossible,
    closed: closed ?? this.closed,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Assignment &&
      other.id == id &&
      other.courseId == courseId &&
      other.title == title &&
      other.description == description &&
      other.rubric == rubric &&
      other.sourceRubricId == sourceRubricId &&
      other.dueDate == dueDate &&
      other.pointsPossible == pointsPossible &&
      other.closed == closed &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, title, rubric, dueDate, closed);
}
