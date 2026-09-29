import 'package:meta/meta.dart';
import 'package:rubric/domain/ids.dart';

/// A class/section a teacher grades (named Course to avoid Dart's `class`).
@immutable
class Course {
  const new({
    required this.id,
    required this.name,
    required this.createdAt,
    this.section = '',
    this.term = '',
    this.archived = false,
  });

  factory create({
    required String name,
    String section = '',
    String term = '',
    DateTime? now,
  }) => Course(
    id: newId(),
    name: name,
    section: section,
    term: term,
    createdAt: now ?? DateTime.now(),
  );

  final String id;
  final String name;
  final String section;
  final String term;
  final bool archived;
  final DateTime createdAt;

  /// "Period 3 · Fall 2026", skipping empty parts.
  String get subtitle =>
      [section, term].where((s) => s.trim().isNotEmpty).join(' · ');

  Course copyWith({
    String? name,
    String? section,
    String? term,
    bool? archived,
  }) => Course(
    id: id,
    name: name ?? this.name,
    section: section ?? this.section,
    term: term ?? this.term,
    archived: archived ?? this.archived,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Course &&
      other.id == id &&
      other.name == name &&
      other.section == section &&
      other.term == term &&
      other.archived == archived &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, section, term, archived, createdAt);
}

@immutable
class Student {
  const new({
    required this.id,
    required this.courseId,
    required this.firstName,
    required this.lastName,
    this.studentNumber = '',
    this.email = '',
    this.notes = '',
    this.archived = false,
  });

  factory create({
    required String courseId,
    required String firstName,
    String lastName = '',
    String studentNumber = '',
    String email = '',
  }) => Student(
    id: newId(),
    courseId: courseId,
    firstName: firstName,
    lastName: lastName,
    studentNumber: studentNumber,
    email: email,
  );

  final String id;
  final String courseId;
  final String firstName;
  final String lastName;
  final String studentNumber;
  final String email;
  final String notes;
  final bool archived;

  String get displayName =>
      [firstName, lastName].where((s) => s.trim().isNotEmpty).join(' ');

  /// "Lovelace, Ada" — the order gradebooks sort and export by.
  String get sortName => lastName.trim().isEmpty
      ? firstName
      : '${lastName.trim()}, ${firstName.trim()}';

  String get initials {
    final parts = [firstName, lastName].where((s) => s.trim().isNotEmpty);
    return parts.map((p) => p.trim()[0].toUpperCase()).join();
  }

  Student copyWith({
    String? firstName,
    String? lastName,
    String? studentNumber,
    String? email,
    String? notes,
    bool? archived,
    String? courseId,
  }) => Student(
    id: id,
    courseId: courseId ?? this.courseId,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    studentNumber: studentNumber ?? this.studentNumber,
    email: email ?? this.email,
    notes: notes ?? this.notes,
    archived: archived ?? this.archived,
  );

  @override
  bool operator ==(Object other) =>
      other is Student &&
      other.id == id &&
      other.courseId == courseId &&
      other.firstName == firstName &&
      other.lastName == lastName &&
      other.studentNumber == studentNumber &&
      other.email == email &&
      other.notes == notes &&
      other.archived == archived;

  @override
  int get hashCode => Object.hash(
    id,
    courseId,
    firstName,
    lastName,
    studentNumber,
    email,
    notes,
    archived,
  );
}

int compareStudents(Student a, Student b) {
  final byLast = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
  return byLast != 0
      ? byLast
      : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
}
