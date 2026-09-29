import 'package:collection/collection.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/rubric.dart';

/// The distinct non-empty subjects in [rubrics], case-insensitively deduped
/// (the first spelling wins) and sorted alphabetically.
List<String> subjectsOf(Iterable<Rubric> rubrics) {
  final bySubject = <String, String>{};
  for (final r in rubrics) {
    final subject = r.subject.trim();
    if (subject.isEmpty) continue;
    bySubject.putIfAbsent(subject.toLowerCase(), () => subject);
  }
  return bySubject.values.sorted(
    (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
  );
}

/// Whether every word of [query] appears in [rubric]'s title or subject (or
/// in [extra], e.g. a template's grade band). An empty query matches.
bool matchesQuery(Rubric rubric, String query, {String extra = ''}) {
  final haystack = '${rubric.title} ${rubric.subject} $extra'.toLowerCase();
  return query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .every(haystack.contains);
}

/// [rubrics] matching [query] (see [matchesQuery]) and, when [subject] is
/// set, whose subject is it (ignoring case). Order is preserved.
List<Rubric> filterRubrics(
  Iterable<Rubric> rubrics, {
  String query = '',
  String? subject,
}) {
  final wanted = subject?.trim().toLowerCase();
  return [
    for (final r in rubrics)
      if ((wanted == null || r.subject.trim().toLowerCase() == wanted) &&
          matchesQuery(r, query))
        r,
  ];
}

/// How many [assignments] were created from the library rubric [rubricId].
int usageCount(Iterable<Assignment> assignments, String rubricId) =>
    assignments.where((a) => a.sourceRubricId == rubricId).length;

/// Formats a point or percentage value without a trailing `.0`.
String formatNumber(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(1);
