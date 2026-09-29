import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rubric/data/backup_service.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/l10n/l10n.dart';

/// One line per kind of record: "12 students".
///
/// With [skipEmpty], kinds with no records are left out (but rubrics and
/// classes always show, so an empty file still says so).
List<String> backupContentLines(
  AppLocalizations l10n,
  BackupDocument doc, {
  bool skipEmpty = false,
}) {
  bool show(int count) => !skipEmpty || count > 0;
  return [
    l10n.backupCountRubrics(doc.rubrics.length - doc.templateCount),
    if (doc.templateCount > 0) l10n.backupCountTemplates(doc.templateCount),
    l10n.backupCountClasses(doc.courses.length),
    if (show(doc.students.length))
      l10n.backupCountStudents(doc.students.length),
    if (show(doc.assignments.length))
      l10n.backupCountAssignments(doc.assignments.length),
    if (show(doc.evaluations.length))
      l10n.backupCountEvaluations(doc.evaluations.length),
    if (show(doc.commentSnippets.length))
      l10n.backupCountComments(doc.commentSnippets.length),
  ];
}

/// Shows what a backup file holds and asks how to restore it. Resolves the
/// chosen [RestoreMode], or null when dismissed.
Future<RestoreMode?> showRestoreSheet(
  BuildContext context, {
  required BackupDocument doc,
  required RestorePreview preview,
}) => showRubricSheet<RestoreMode>(
  context: context,
  child: RestoreSheet(doc: doc, preview: preview),
);

class RestoreSheet extends StatefulWidget {
  const new({required this.doc, required this.preview, super.key});

  final BackupDocument doc;
  final RestorePreview preview;

  @override
  State<RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends State<RestoreSheet> {
  RestoreMode _mode = RestoreMode.merge;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final doc = widget.doc;
    final exported = DateFormat.yMMMMd(l10n.localeName)
        .add_jm()
        .format(doc.exportedAt);

    return RubricSheet(
      title: l10n.backupRestoreSheetTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHint(l10n.backupRestoreFrom(exported)),
          const SizedBox(height: Insets.md),
          RubricFormWell(
            child: Text(
              backupContentLines(l10n, doc, skipEmpty: true).join(' · '),
              style: RubricTextStyles.listTitle.copyWith(height: 1.4),
            ),
          ),
          const SizedBox(height: Insets.lg),
          Container(
            decoration: BoxDecoration(
              color: primary,
              borderRadius: Corners.card,
            ),
            padding: const EdgeInsets.all(4),
            child: SegmentedToggle<RestoreMode>(
              segments: {
                RestoreMode.merge: l10n.backupModeMerge,
                RestoreMode.replace: l10n.backupModeReplace,
              },
              selected: _mode,
              onChanged: (mode) => setState(() => _mode = mode),
            ),
          ),
          const SizedBox(height: Insets.md),
          Text(switch (_mode) {
            RestoreMode.merge => l10n.backupModeMergeExplain(
              widget.preview.added,
              widget.preview.alreadyHere,
            ),
            RestoreMode.replace => l10n.backupModeReplaceExplain,
          }, style: RubricTextStyles.bodySmall),
          const SizedBox(height: Insets.xl),
          AccentButton(
            key: const ValueKey('restoreConfirm'),
            label: switch (_mode) {
              RestoreMode.merge => l10n.backupRestoreMergeAction,
              RestoreMode.replace => l10n.backupRestoreReplaceAction,
            },
            widthFactor: .12,
            onTap: () => Navigator.of(context).pop(_mode),
          ),
        ],
      ),
    );
  }
}
