import 'package:collection/collection.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/features/export/export_labels.dart';
import 'package:rubric/l10n/l10n.dart';

// Pure CSV builders. No I/O: they return the file's text so the column layout,
// escaping and number formatting are unit-testable; export_actions.dart writes
// and shares the result.

/// Excel-friendly: UTF-8 BOM so accents survive, CRLF rows, comma separated.
final _csv = Csv(addBom: true, autoDetect: false);

/// yyyy-MM-dd, the one date format every spreadsheet parses unambiguously.
final isoDate = DateFormat('yyyy-MM-dd');

/// One row per student: identity, status, every objective score, every group
/// percentage, then the grade of record.
///
/// Objective cells hold the percentage on a simple rubric and the level label
/// on a detailed one (what the teacher actually picked). Percent columns are
/// bare numbers (no `%`) so spreadsheets can sum and average them.
String buildAssignmentCsv({
  required AppLocalizations l10n,
  required Assignment assignment,
  required List<Student> students,
  required List<Evaluation> evaluations,
}) {
  final rubric = assignment.rubric;
  final byStudent = {for (final e in evaluations) e.studentId: e};
  final header = [
    l10n.exportCsvLastName,
    l10n.exportCsvFirstName,
    l10n.exportCsvStudentNumber,
    l10n.exportCsvStatus,
    for (final o in rubric.objectives) _text(o.title),
    for (final g in rubric.groups) l10n.exportCsvGroupPercent(_text(g.title)),
    l10n.exportCsvFinalPercent,
    l10n.exportCsvLetter,
    l10n.exportCsvPoints(csvNumber(assignment.pointsPossible)),
    l10n.exportCsvComment,
  ];

  final rows = [
    for (final student in students.sorted(compareStudents))
      _assignmentRow(l10n, assignment, student, byStudent[student.id]),
  ];
  return _csv.encode([header, ...rows]);
}

List<Object> _assignmentRow(
  AppLocalizations l10n,
  Assignment assignment,
  Student student,
  Evaluation? evaluation,
) {
  final rubric = assignment.rubric;
  final result = evaluation == null ? null : Scoring.score(rubric, evaluation);
  String objectiveCell(Objective o) {
    final score = evaluation?.scores[o.id];
    if (rubric.mode == GradingMode.detailed && score is LevelScore) {
      return rubric.levelById(score.levelId)?.label ?? '';
    }
    return csvNumber(result?.objectivePercents[o.id]);
  }

  return [
    _text(student.lastName),
    _text(student.firstName),
    _text(student.studentNumber),
    statusLabel(l10n, evaluation?.status ?? EvaluationStatus.notStarted),
    for (final o in rubric.objectives) objectiveCell(o),
    for (final g in rubric.groups) csvNumber(result?.groupPercents[g.id]),
    csvNumber(result?.percent),
    result?.letter ?? '',
    csvNumber(
      result == null ? null : Scoring.points(result, assignment.pointsPossible),
    ),
    _text(evaluation?.comment ?? ''),
  ];
}

/// Students down, assignments across (in the order given), the grade of
/// record in each cell, and the student's course average last.
String buildGradebookCsv({
  required AppLocalizations l10n,
  required List<Assignment> assignments,
  required List<Student> students,
  required List<Evaluation> evaluations,
}) {
  final byKey = {for (final e in evaluations) (e.assignmentId, e.studentId): e};
  final header = [
    l10n.exportCsvLastName,
    l10n.exportCsvFirstName,
    l10n.exportCsvStudentNumber,
    for (final a in assignments)
      if (a.dueDate case final due?)
        l10n.exportCsvAssignmentDue(_text(a.title), isoDate.format(due))
      else
        _text(a.title),
    l10n.exportCsvAverage,
  ];

  final rows = [
    for (final student in students.sorted(compareStudents))
      () {
        final grades = [
          for (final a in assignments)
            (
              assignment: a,
              percent: switch (byKey[(a.id, student.id)]) {
                null => null,
                final e => Scoring.score(a.rubric, e).percent,
              },
            ),
        ];
        return [
          _text(student.lastName),
          _text(student.firstName),
          _text(student.studentNumber),
          for (final g in grades) csvNumber(g.percent),
          csvNumber(
            courseAverage([
              for (final g in grades)
                (
                  percent: g.percent,
                  pointsPossible: g.assignment.pointsPossible,
                ),
            ]),
          ),
        ];
      }(),
  ];
  return _csv.encode([header, ...rows]);
}

/// Assignments in gradebook column order: soonest due first, undated last
/// (newest first among those), the order the class screens list them in.
List<Assignment> gradebookOrder(Iterable<Assignment> assignments) =>
    assignments.sorted((a, b) {
      final (ad, bd) = (a.dueDate, b.dueDate);
      if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
      if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
      return b.createdAt.compareTo(a.createdAt);
    });

/// A student's course average: points earned over points possible across the
/// assignments that have a grade of record, as 0–100. Ungraded and excused
/// work (null percent) is left out rather than counted as zero. Null when
/// nothing is graded.
double? courseAverage(
  Iterable<({double? percent, double pointsPossible})> grades,
) {
  var earned = 0.0;
  var possible = 0.0;
  for (final g in grades) {
    if (g.percent == null || g.pointsPossible <= 0) continue;
    earned += g.percent! / 100 * g.pointsPossible;
    possible += g.pointsPossible;
  }
  return possible == 0 ? null : earned / possible * 100;
}

/// Up to two decimals, trailing zeros dropped; empty for null.
String csvNumber(double? value) {
  if (value == null) return '';
  final fixed = value.toStringAsFixed(2);
  return fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
      : fixed;
}

/// Neutralises spreadsheet formula injection: a name or comment typed as
/// `=HYPERLINK(...)` must open as text, not run. Prefixing a quote is what
/// Excel and Sheets themselves do for literal text.
String _text(String value) =>
    value.isNotEmpty && '=+-@\t\r'.contains(value[0]) ? "'$value" : value;
