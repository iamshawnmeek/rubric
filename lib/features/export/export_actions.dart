import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/export/csv_builders.dart';
import 'package:rubric/features/export/export_platform.dart';
import 'package:rubric/features/export/export_sheet.dart';
import 'package:rubric/features/export/pdf_builders.dart';
import 'package:rubric/features/export/pdf_style.dart';
import 'package:rubric/l10n/l10n.dart';

// The public export surface every feature calls. Signatures are the contract:
// other leaves call them, so change a signature only together with its
// callers. Each one gathers its data through the repositories, hands it to a
// pure builder (csv_builders.dart / pdf_builders.dart), then prints or shares
// through [ExportPlatform].

/// Print or share a blank rubric as a PDF.
Future<void> exportRubricPdf(BuildContext context, Rubric rubric) => _exportPdf(
  context,
  name: rubric.title.trim().isEmpty
      ? context.l10n.exportUntitledRubric
      : rubric.title,
  build: (l10n, fonts, paper) =>
      buildRubricPdf(l10n: l10n, rubric: rubric, fonts: fonts, paper: paper),
);

/// One student's graded rubric with feedback, as a PDF.
Future<void> exportStudentReportPdf(
  BuildContext context, {
  required Assignment assignment,
  required Student student,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return _exportPdf(
    context,
    name: '${assignment.title} - ${student.displayName}',
    build: (l10n, fonts, paper) async => await buildStudentReportPdf(
      l10n: l10n,
      report: (await _reports(container, assignment, [student])).single,
      fonts: fonts,
      paper: paper,
    ),
  );
}

/// Every student's graded rubric for an assignment, one per page, as a PDF.
Future<void> exportAssignmentReportsPdf(
  BuildContext context, {
  required Assignment assignment,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return _exportPdf(
    context,
    name: context.l10n.exportReportsName(assignment.title),
    build: (l10n, fonts, paper) async {
      final evaluations = await container
          .read(assignmentRepositoryProvider)
          .evaluations(assignment.id);
      final students = await _roster(
        container,
        assignment.courseId,
        evaluations,
      );
      return await buildAssignmentReportsPdf(
        l10n: l10n,
        reports: await _reports(container, assignment, students, evaluations),
        fonts: fonts,
        paper: paper,
        title: assignment.title,
      );
    },
  );
}

/// Scores for one assignment (per objective, per group, total) as CSV.
Future<void> exportAssignmentCsv(
  BuildContext context, {
  required Assignment assignment,
}) => _exportCsv(
  context,
  filename: exportFilename([
    assignment.title,
    context.l10n.exportScoresFileSuffix,
  ], 'csv'),
  subject: assignment.title,
  build: (container, l10n) async {
    final evaluations = await container
        .read(assignmentRepositoryProvider)
        .evaluations(assignment.id);
    return buildAssignmentCsv(
      l10n: l10n,
      assignment: assignment,
      students: await _roster(container, assignment.courseId, evaluations),
      evaluations: evaluations,
    );
  },
);

/// The whole course gradebook (students × assignments) as CSV.
Future<void> exportGradebookCsv(
  BuildContext context, {
  required Course course,
}) => _exportCsv(
  context,
  filename: exportFilename([
    course.name,
    context.l10n.exportGradebookFileSuffix,
  ], 'csv'),
  subject: course.name,
  build: (container, l10n) async {
    final repo = container.read(assignmentRepositoryProvider);
    final assignments = gradebookOrder(
      (await repo.all()).where((a) => a.courseId == course.id),
    );
    final ids = assignments.map((a) => a.id).toSet();
    final evaluations = (await repo.allEvaluations())
        .where((e) => ids.contains(e.assignmentId))
        .toList();
    return buildGradebookCsv(
      l10n: l10n,
      assignments: assignments,
      students: await _roster(container, course.id, evaluations),
      evaluations: evaluations,
    );
  },
);

/// `essay-scores-2026-09-29.csv`: lowercase, dash-separated, dated, and safe
/// on every filesystem the file may be shared to.
String exportFilename(List<String> parts, String extension, {DateTime? now}) {
  final slug = [...parts, isoDate.format(now ?? DateTime.now())]
      .map(
        (part) => part
            .toLowerCase()
            .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
            .replaceAll(RegExp(r'^-+|-+$'), ''),
      )
      .where((part) => part.isNotEmpty)
      .join('-');
  final trimmed = slug.length > 80 ? slug.substring(0, 80) : slug;
  return '$trimmed.$extension';
}

// ---- Plumbing ----

Future<void> _exportPdf(
  BuildContext context, {
  required String name,
  required Future<Uint8List> Function(
    AppLocalizations l10n,
    ExportFonts fonts,
    PdfPageFormat? paper,
  )
  build,
}) async {
  final l10n = context.l10n;
  final platform = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(exportPlatformProvider);
  final origin = _shareOrigin(context);

  final destination = await showPdfDestinationSheet(
    context,
    documentName: name,
  );
  if (destination == null) return;
  try {
    final fonts = await platform.loadFonts();
    switch (destination) {
      case PdfDestination.print:
        await platform.printPdf(
          name: name,
          build: (paper) => build(l10n, fonts, paper),
        );
      case PdfDestination.share:
        await platform.sharePdf(
          bytes: await build(l10n, fonts, null),
          filename: exportFilename([name], 'pdf'),
          origin: origin,
        );
    }
  } on Object catch (error, stack) {
    _report(error, stack);
    if (context.mounted) showRubricSnack(context, l10n.exportFailed);
  }
}

Future<void> _exportCsv(
  BuildContext context, {
  required String filename,
  required String subject,
  required Future<String> Function(
    ProviderContainer container,
    AppLocalizations l10n,
  )
  build,
}) async {
  final l10n = context.l10n;
  final container = ProviderScope.containerOf(context, listen: false);
  final origin = _shareOrigin(context);
  try {
    final text = await build(container, l10n);
    await container
        .read(exportPlatformProvider)
        .shareFile(
          bytes: Uint8List.fromList(utf8.encode(text)),
          filename: filename,
          mimeType: 'text/csv',
          subject: subject,
          origin: origin,
        );
  } on Object catch (error, stack) {
    _report(error, stack);
    if (context.mounted) showRubricSnack(context, l10n.exportFailed);
  }
}

/// The course's active students, plus any archived student who has work on
/// record here, so a mid-term withdrawal does not silently drop a grade.
Future<List<Student>> _roster(
  ProviderContainer container,
  String courseId,
  List<Evaluation> evaluations,
) async {
  final all = await container
      .read(courseRepositoryProvider)
      .students(courseId, includeArchived: true);
  final graded = evaluations.map((e) => e.studentId).toSet();
  return all.where((s) => !s.archived || graded.contains(s.id)).toList();
}

Future<List<StudentReport>> _reports(
  ProviderContainer container,
  Assignment assignment,
  List<Student> students, [
  List<Evaluation>? evaluations,
]) async {
  final repo = container.read(assignmentRepositoryProvider);
  final course = await container
      .read(courseRepositoryProvider)
      .getCourse(assignment.courseId);
  final byStudent = {
    for (final e in evaluations ?? await repo.evaluations(assignment.id))
      e.studentId: e,
  };
  final now = DateTime.now();
  return [
    for (final student in students..sort(compareStudents))
      StudentReport(
        assignment: assignment,
        student: student,
        evaluation: byStudent[student.id],
        date: now,
        courseName: course?.name ?? '',
        teacherName: container.read(settingsProvider).teacherName,
      ),
  ];
}

/// Where the iPad share popover points from: the widget that asked.
Rect? _shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return null;
}

void _report(Object error, StackTrace stack) =>
    debugPrint('Export failed: $error\n$stack');
