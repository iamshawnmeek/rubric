import 'package:flutter/widgets.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/rubric.dart';

// The public export surface every feature calls. STUB — owned by the export
// leaf, which implements these (PDF via package:pdf/printing, CSV, share
// sheet). Signatures are the contract: other leaves already call them, so
// change a signature only together with its callers.

/// Print or share a blank rubric as a PDF.
Future<void> exportRubricPdf(BuildContext context, Rubric rubric) async =>
    _soon(context);

/// One student's graded rubric with feedback, as a PDF.
Future<void> exportStudentReportPdf(
  BuildContext context, {
  required Assignment assignment,
  required Student student,
}) async => _soon(context);

/// Every student's graded rubric for an assignment, one per page, as a PDF.
Future<void> exportAssignmentReportsPdf(
  BuildContext context, {
  required Assignment assignment,
}) async => _soon(context);

/// Scores for one assignment (per objective, per group, total) as CSV.
Future<void> exportAssignmentCsv(
  BuildContext context, {
  required Assignment assignment,
}) async => _soon(context);

/// The whole course gradebook (students × assignments) as CSV.
Future<void> exportGradebookCsv(
  BuildContext context, {
  required Course course,
}) async => _soon(context);

void _soon(BuildContext context) =>
    showRubricSnack(context, 'Export is coming soon.');
