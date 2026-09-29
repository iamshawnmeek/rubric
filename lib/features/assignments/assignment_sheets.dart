import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/features/assignments/assignment_logic.dart';
import 'package:rubric/features/assignments/assignment_widgets.dart';
import 'package:rubric/l10n/l10n.dart';

enum StudentAction { markMissing, excuse, clearMark, reset }

/// Quick actions for one student's paper. Resolves the chosen action.
Future<StudentAction?> showStudentActions(BuildContext context, HubRow row) {
  final l10n = context.l10n;
  final e = row.evaluation;
  final marked =
      e.status == EvaluationStatus.missing ||
      e.status == EvaluationStatus.excused;
  final blank =
      e.status == EvaluationStatus.notStarted &&
      e.scores.isEmpty &&
      e.comment.isEmpty &&
      e.objectiveComments.isEmpty &&
      e.overridePercent == null &&
      e.penaltyPercent == 0 &&
      !e.late;

  return showRubricSheet<StudentAction>(
    context: context,
    child: Builder(
      builder: (context) {
        void pick(StudentAction a) => Navigator.of(context).pop(a);
        return RubricSheet(
          title: row.student.displayName,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (e.status != EvaluationStatus.missing)
                SheetAction(
                  icon: FontAwesomeIcons.circleExclamation,
                  label: l10n.assignmentsMarkMissing,
                  onTap: () => pick(StudentAction.markMissing),
                ),
              if (e.status != EvaluationStatus.excused)
                SheetAction(
                  icon: FontAwesomeIcons.userSlash,
                  label: l10n.assignmentsExcuse,
                  onTap: () => pick(StudentAction.excuse),
                ),
              if (marked)
                SheetAction(
                  icon: FontAwesomeIcons.arrowRotateLeft,
                  label: e.status == EvaluationStatus.missing
                      ? l10n.assignmentsClearMissing
                      : l10n.assignmentsClearExcused,
                  onTap: () => pick(StudentAction.clearMark),
                ),
              SheetAction(
                icon: FontAwesomeIcons.eraser,
                label: l10n.assignmentsReset,
                destructive: true,
                onTap: blank ? null : () => pick(StudentAction.reset),
              ),
            ],
          ),
        );
      },
    ),
  );
}

enum AssignmentAction {
  edit,
  updateRubric,
  close,
  reopen,
  exportCsv,
  exportPdf,
  delete,
}

/// The hub's overflow menu. Resolves the chosen action.
Future<AssignmentAction?> showAssignmentMenu(
  BuildContext context,
  Assignment assignment,
) {
  final l10n = context.l10n;
  return showRubricSheet<AssignmentAction>(
    context: context,
    child: Builder(
      builder: (context) {
        Widget item(
          AssignmentAction a,
          FaIconData icon,
          String label, {
          bool destructive = false,
        }) => SheetAction(
          key: Key('assignments.menu.${a.name}'),
          icon: icon,
          label: label,
          destructive: destructive,
          onTap: () => Navigator.of(context).pop(a),
        );
        return RubricSheet(
          title: assignment.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              item(
                AssignmentAction.edit,
                FontAwesomeIcons.pen,
                l10n.assignmentsEditDetails,
              ),
              item(
                AssignmentAction.updateRubric,
                FontAwesomeIcons.arrowsRotate,
                l10n.assignmentsUpdateRubric,
              ),
              if (assignment.closed)
                item(
                  AssignmentAction.reopen,
                  FontAwesomeIcons.lockOpen,
                  l10n.assignmentsReopen,
                )
              else
                item(
                  AssignmentAction.close,
                  FontAwesomeIcons.lock,
                  l10n.assignmentsClose,
                ),
              item(
                AssignmentAction.exportCsv,
                FontAwesomeIcons.fileCsv,
                l10n.assignmentsExportCsv,
              ),
              item(
                AssignmentAction.exportPdf,
                FontAwesomeIcons.filePdf,
                l10n.assignmentsExportPdf,
              ),
              item(
                AssignmentAction.delete,
                FontAwesomeIcons.trashCan,
                l10n.assignmentsDelete,
                destructive: true,
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Edit title, description, due date and points. Resolves the edited
/// assignment, or null when cancelled.
Future<Assignment?> showEditDetails(
  BuildContext context,
  Assignment assignment,
) => showRubricSheet<Assignment>(
  context: context,
  child: _EditDetailsSheet(assignment),
);

class _EditDetailsSheet extends StatefulWidget {
  const new(this.assignment);

  final Assignment assignment;

  @override
  State<_EditDetailsSheet> createState() => _EditDetailsSheetState();
}

class _EditDetailsSheetState extends State<_EditDetailsSheet> {
  late final _title = TextEditingController(text: widget.assignment.title);
  late final _description = TextEditingController(
    text: widget.assignment.description,
  );
  late final _points = TextEditingController(
    text: formatPoints(widget.assignment.pointsPossible),
  );
  late DateTime? _dueDate = widget.assignment.dueDate;

  @override
  void initState() {
    super.initState();
    _title.addListener(_refresh);
    _points.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _points.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty && parsePoints(_points.text) != null;

  void _save() => Navigator.of(context).pop(
    widget.assignment.copyWith(
      title: _title.text.trim(),
      description: _description.text.trim(),
      dueDate: _dueDate,
      clearDueDate: _dueDate == null,
      pointsPossible: parsePoints(_points.text),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RubricSheet(
      title: l10n.assignmentsEditDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AssignmentDetailsFields(
            title: _title,
            description: _description,
            points: _points,
            dueDate: _dueDate,
            onDueDateChanged: (d) => setState(() => _dueDate = d),
          ),
          const SizedBox(height: Insets.lg),
          FilledButton(
            key: const Key('assignments.saveDetails'),
            onPressed: _valid ? _save : null,
            child: Text(l10n.assignmentsSave),
          ),
        ],
      ),
    );
  }
}
