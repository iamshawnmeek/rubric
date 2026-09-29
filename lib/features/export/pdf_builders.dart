import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:meta/meta.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/export/export_labels.dart';
import 'package:rubric/features/export/pdf_style.dart';
import 'package:rubric/l10n/l10n.dart';

// Pure PDF builders: data in, bytes out. Printing and sharing live in
// export_actions.dart. Detailed rubrics are laid out landscape as the classic
// objectives × levels grid; simple ones portrait.

/// Everything one student's report needs.
@immutable
class StudentReport {
  const new({
    required this.assignment,
    required this.student,
    required this.evaluation,
    required this.date,
    this.courseName = '',
    this.teacherName = '',
  });

  final Assignment assignment;
  final Student student;

  /// Null when the student has not been graded at all.
  final Evaluation? evaluation;
  final DateTime date;
  final String courseName;
  final String teacherName;
}

/// US Letter unless the print dialog supplies a paper size.
PdfPageFormat pageFormatFor(Rubric rubric, [PdfPageFormat? paper]) {
  final base = paper ?? PdfPageFormat.letter;
  return rubric.mode == GradingMode.detailed ? base.landscape : base.portrait;
}

/// A blank rubric, ready to print and hand out.
Future<Uint8List> buildRubricPdf({
  required AppLocalizations l10n,
  required Rubric rubric,
  required ExportFonts fonts,
  PdfPageFormat? paper,
}) {
  final b = _Builder(l10n, PdfStyles(fonts));
  final doc =
      pw.Document(title: rubric.title, creator: l10n.appTitle, theme: b.s.theme)
        ..addPage(
          b.page(
            format: pageFormatFor(rubric, paper),
            children: b.rubric(rubric),
          ),
        );
  return doc.save();
}

/// One student's graded rubric with feedback.
Future<Uint8List> buildStudentReportPdf({
  required AppLocalizations l10n,
  required StudentReport report,
  required ExportFonts fonts,
  PdfPageFormat? paper,
}) => buildAssignmentReportsPdf(
  l10n: l10n,
  reports: [report],
  fonts: fonts,
  paper: paper,
  title: '${report.assignment.title} - ${report.student.displayName}',
);

/// Every report in [reports], each starting on a new page.
Future<Uint8List> buildAssignmentReportsPdf({
  required AppLocalizations l10n,
  required List<StudentReport> reports,
  required ExportFonts fonts,
  PdfPageFormat? paper,
  String? title,
}) {
  final b = _Builder(l10n, PdfStyles(fonts));
  final doc = pw.Document(
    title: title ?? reports.firstOrNull?.assignment.title,
    creator: l10n.appTitle,
    theme: b.s.theme,
  );
  for (final report in reports) {
    doc.addPage(
      b.page(
        format: pageFormatFor(report.assignment.rubric, paper),
        children: b.report(report),
      ),
    );
  }
  if (reports.isEmpty) {
    doc.addPage(
      b.page(
        format: paper ?? PdfPageFormat.letter,
        children: [pw.Text(l10n.exportPdfNoStudents, style: b.s.body)],
      ),
    );
  }
  return doc.save();
}

class _Builder {
  new(this.l10n, this.s);

  final AppLocalizations l10n;
  final PdfStyles s;

  pw.MultiPage page({
    required PdfPageFormat format,
    required List<pw.Widget> children,
  }) => pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: format,
      margin: const pw.EdgeInsets.fromLTRB(40, 32, 40, 32),
      theme: s.theme,
    ),
    header: (context) => pw.Container(
      height: 4,
      width: 48,
      margin: const pw.EdgeInsets.only(bottom: 16),
      color: PdfPalette.accent,
    ),
    footer: (context) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            l10n.appTitle,
            style: s.label.copyWith(color: PdfPalette.primary),
          ),
          pw.Text(
            l10n.exportPdfPageOf(context.pageNumber, context.pagesCount),
            style: s.meta,
          ),
        ],
      ),
    ),
    build: (context) => children,
  );

  // ---- Rubric ----

  List<pw.Widget> rubric(Rubric rubric) => [
    pw.Text(rubric.title, style: s.title),
    pw.SizedBox(height: 4),
    pw.Text(
      [
        if (rubric.subject.trim().isNotEmpty) rubric.subject.trim(),
        modeLabel(l10n, rubric.mode),
        l10n.exportPdfObjectiveCount(rubric.objectives.length),
      ].join('  ·  '),
      style: s.meta,
    ),
    if (rubric.description.trim().isNotEmpty) ...[
      pw.SizedBox(height: 10),
      pw.Text(rubric.description.trim(), style: s.body),
    ],
    pw.SizedBox(height: 18),
    for (final group in rubric.groups) ...[
      _groupHeading(group),
      pw.SizedBox(height: 6),
      if (rubric.mode == GradingMode.detailed)
        _levelGrid(rubric, group)
      else
        _blankScoreTable(group),
      pw.SizedBox(height: 16),
    ],
    _scaleTable(rubric),
  ];

  pw.Widget _groupHeading(RubricGroup group, {String? trailing}) => pw.Row(
    children: [
      pw.Expanded(child: pw.Text(group.title, style: s.section)),
      if (trailing != null) ...[
        pw.Text(trailing, style: s.meta),
        pw.SizedBox(width: 8),
      ],
      _pill(l10n.exportPdfWeight(group.weight)),
    ],
  );

  pw.Widget _pill(String text) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: pw.BoxDecoration(
      color: PdfPalette.accent,
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Text(text, style: s.bodyStrong.copyWith(fontSize: 9)),
  );

  pw.Widget _blankScoreTable(RubricGroup group) => _table(
    widths: const {
      0: pw.FlexColumnWidth(3),
      1: pw.FlexColumnWidth(5),
      2: pw.FixedColumnWidth(70),
    },
    header: [
      l10n.exportPdfObjective,
      l10n.exportPdfDescription,
      l10n.exportPdfScore,
    ],
    rows: [
      for (final o in group.objectives)
        [
          pw.Text(o.title, style: s.bodyStrong),
          pw.Text(o.description, style: s.small),
          pw.SizedBox(height: 22),
        ],
    ],
  );

  pw.Widget _levelGrid(
    Rubric rubric,
    RubricGroup group, {
    Evaluation? evaluation,
  }) {
    final objectiveWidth = rubric.levels.length > 4 ? 1.4 : 1.8;
    return _table(
      widths: {
        0: pw.FlexColumnWidth(objectiveWidth),
        for (var i = 0; i < rubric.levels.length; i++)
          i + 1: const pw.FlexColumnWidth(2),
      },
      header: [
        l10n.exportPdfObjective,
        for (final l in rubric.levels)
          l10n.exportPdfLevelHeader(l.label, _points(l.points)),
      ],
      rows: [
        for (final o in group.objectives)
          [
            _objectiveCell(o, evaluation),
            for (final l in rubric.levels)
              _levelCell(
                o.descriptors[l.id] ?? '',
                achieved: switch (evaluation?.scores[o.id]) {
                  LevelScore(:final levelId) => levelId == l.id,
                  _ => false,
                },
              ),
          ],
      ],
      highlight: evaluation == null
          ? null
          : (row, column) {
              if (column == 0) return false;
              final o = group.objectives[row];
              final score = evaluation.scores[o.id];
              return score is LevelScore &&
                  score.levelId == rubric.levels[column - 1].id;
            },
    );
  }

  pw.Widget _objectiveCell(Objective o, Evaluation? evaluation) {
    final comment = evaluation?.objectiveComments[o.id]?.trim() ?? '';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(o.title, style: s.bodyStrong),
        if (o.description.trim().isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(o.description.trim(), style: s.small),
        ],
        if (comment.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            l10n.exportPdfFeedbackInline(comment),
            style: s.small.copyWith(color: PdfPalette.heading),
          ),
        ],
      ],
    );
  }

  /// The achieved level is marked three ways so it survives greyscale
  /// printing: an orange fill (from [_table]), bold type and a label.
  pw.Widget _levelCell(String descriptor, {required bool achieved}) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (achieved) ...[
            pw.Text(
              l10n.exportPdfAchieved.toUpperCase(),
              style: s.label.copyWith(color: PdfPalette.ink),
            ),
            pw.SizedBox(height: 2),
          ],
          pw.Text(
            descriptor,
            style: achieved ? s.body.copyWith(fontSize: 8.5) : s.small,
          ),
        ],
      );

  pw.Widget _scaleTable(Rubric rubric) {
    final bands = rubric.scale.bands;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(l10n.exportPdfGradingScale, style: s.section),
        pw.SizedBox(height: 6),
        pw.SizedBox(
          width: 260,
          child: _table(
            widths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth(2)},
            header: [l10n.exportPdfGrade, l10n.exportPdfRange],
            rows: [
              for (var i = 0; i < bands.length; i++)
                [
                  pw.Text(bands[i].letter, style: s.bodyStrong),
                  pw.Text(
                    l10n.exportPdfRangeValue(
                      _points(bands[i].min),
                      _points(rubric.scale.upperBoundOf(i)),
                    ),
                    style: s.body,
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  // ---- Student report ----

  List<pw.Widget> report(StudentReport r) {
    final rubric = r.assignment.rubric;
    final evaluation = r.evaluation;
    final result = evaluation == null
        ? null
        : Scoring.score(rubric, evaluation);
    final student = r.student;

    return [
      pw.Text(r.assignment.title, style: s.title),
      pw.SizedBox(height: 4),
      pw.Text(student.displayName, style: s.subtitle),
      pw.SizedBox(height: 4),
      pw.Text(
        [
          if (r.courseName.trim().isNotEmpty) r.courseName.trim(),
          if (student.studentNumber.trim().isNotEmpty)
            l10n.exportPdfStudentNumber(student.studentNumber.trim()),
          DateFormat.yMMMd(l10n.localeName).format(r.date),
          if (r.teacherName.trim().isNotEmpty) r.teacherName.trim(),
        ].join('  ·  '),
        style: s.meta,
      ),
      pw.SizedBox(height: 16),
      _gradePanel(r, evaluation, result),
      ..._notes(evaluation, result),
      pw.SizedBox(height: 18),
      for (final group in rubric.groups) ...[
        _groupHeading(
          group,
          trailing: result?.groupPercents[group.id] == null
              ? null
              : l10n.exportPdfGroupScore(
                  formatPercent(result!.groupPercents[group.id]),
                ),
        ),
        pw.SizedBox(height: 6),
        if (rubric.mode == GradingMode.detailed)
          _levelGrid(rubric, group, evaluation: evaluation)
        else
          _simpleScoreTable(group, evaluation, result),
        pw.SizedBox(height: 16),
      ],
      // One unbreakable block so the heading never ends a page alone.
      if (evaluation != null && evaluation.comment.trim().isNotEmpty)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(l10n.exportPdfComments, style: s.section),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfPalette.band,
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text(evaluation.comment.trim(), style: s.body),
            ),
          ],
        ),
    ];
  }

  pw.Widget _gradePanel(
    StudentReport r,
    Evaluation? evaluation,
    ScoreResult? result,
  ) {
    final status = evaluation?.status ?? EvaluationStatus.notStarted;
    final percent = result?.percent;
    final String headline;
    final String detail;
    if (status == EvaluationStatus.excused) {
      headline = l10n.exportStatusExcused;
      detail = l10n.exportPdfExcusedDetail;
    } else if (percent == null) {
      headline = l10n.exportPdfNotGraded;
      detail = statusLabel(l10n, status);
    } else {
      headline = formatPercent(percent);
      detail = l10n.exportPdfPoints(
        _points(Scoring.points(result!, r.assignment.pointsPossible)!),
        _points(r.assignment.pointsPossible),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: pw.BoxDecoration(
        color: PdfPalette.band,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(l10n.exportPdfFinalGrade.toUpperCase(), style: s.label),
                pw.SizedBox(height: 4),
                pw.Text(headline, style: s.grade),
                pw.SizedBox(height: 2),
                pw.Text(detail, style: s.meta),
              ],
            ),
          ),
          if (result?.letter case final letter?)
            pw.Container(
              width: 64,
              height: 64,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: PdfPalette.accent,
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text(
                letter,
                style: s.grade.copyWith(fontSize: letter.length > 2 ? 16 : 28),
              ),
            ),
        ],
      ),
    );
  }

  List<pw.Widget> _notes(Evaluation? evaluation, ScoreResult? result) {
    if (evaluation == null) return const [];
    final notes = [
      if (evaluation.status == EvaluationStatus.missing)
        l10n.exportPdfMissingNote,
      if (evaluation.late && evaluation.penaltyPercent <= 0)
        l10n.exportPdfLateNote,
      if (evaluation.penaltyPercent > 0 &&
          evaluation.overridePercent == null &&
          result?.rawPercent != null)
        l10n.exportPdfPenaltyNote(
          _points(evaluation.penaltyPercent),
          formatPercent(result!.rawPercent),
        ),
      if (evaluation.overridePercent != null &&
          evaluation.status != EvaluationStatus.excused)
        l10n.exportPdfOverrideNote(formatPercent(result?.rawPercent)),
    ];
    return [
      for (final note in notes) ...[
        pw.SizedBox(height: 6),
        pw.Text(note, style: s.meta.copyWith(color: PdfPalette.heading)),
      ],
    ];
  }

  pw.Widget _simpleScoreTable(
    RubricGroup group,
    Evaluation? evaluation,
    ScoreResult? result,
  ) => _table(
    widths: const {
      0: pw.FlexColumnWidth(3),
      1: pw.FixedColumnWidth(60),
      2: pw.FlexColumnWidth(4),
    },
    header: [
      l10n.exportPdfObjective,
      l10n.exportPdfScore,
      l10n.exportPdfFeedback,
    ],
    rows: [
      for (final o in group.objectives)
        [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(o.title, style: s.bodyStrong),
              if (o.description.trim().isNotEmpty)
                pw.Text(o.description.trim(), style: s.small),
            ],
          ),
          pw.Text(
            formatPercent(result?.objectivePercents[o.id]),
            style: s.bodyStrong,
          ),
          pw.Text(
            evaluation?.objectiveComments[o.id]?.trim() ?? '',
            style: s.small,
          ),
        ],
    ],
  );

  // ---- Shared ----

  /// A table with a dark purple header row, pale banding and thin rules.
  /// [highlight] marks body cells (row, column) filled with the accent tint.
  pw.Widget _table({
    required Map<int, pw.TableColumnWidth> widths,
    required List<String> header,
    required List<List<pw.Widget>> rows,
    bool Function(int row, int column)? highlight,
  }) {
    const pad = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5);
    return pw.Table(
      columnWidths: widths,
      border: pw.TableBorder.symmetric(
        inside: pw.BorderSide(color: PdfPalette.rule, width: .5),
        outside: pw.BorderSide(color: PdfPalette.rule, width: .5),
      ),
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: PdfPalette.heading),
          children: [
            for (final h in header)
              pw.Padding(
                padding: pad,
                child: pw.Text(h, style: s.tableHeader),
              ),
          ],
        ),
        for (var r = 0; r < rows.length; r++)
          pw.TableRow(
            decoration: r.isOdd
                ? pw.BoxDecoration(color: PdfPalette.band)
                : null,
            children: [
              for (var c = 0; c < rows[r].length; c++)
                pw.Container(
                  padding: pad,
                  decoration: (highlight?.call(r, c) ?? false)
                      ? pw.BoxDecoration(
                          color: PdfPalette.highlight,
                          border: pw.Border.all(
                            color: PdfPalette.accent,
                            width: 1.5,
                          ),
                        )
                      : null,
                  child: rows[r][c],
                ),
            ],
          ),
      ],
    );
  }

  /// 4 → "4", 2.5 → "2.5".
  String _points(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}
