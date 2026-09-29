import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/l10n/l10n.dart';

/// Content never stretches past this on tablets.
const double maxContentWidth = 720;

/// Page gutters that grow on wide screens so content stays [maxContentWidth].
EdgeInsets contentGutter(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final side = math.max(Insets.lg, (width - maxContentWidth) / 2);
  return EdgeInsets.symmetric(horizontal: side);
}

String formatDueDate(BuildContext context, DateTime date) =>
    DateFormat.yMMMEd(Localizations.localeOf(context).toString()).format(date);

/// "12.5" → "12.5", "100.0" → "100".
String formatPoints(double points) => points == points.roundToDouble()
    ? points.toStringAsFixed(0)
    : points.toString();

extension EvaluationStatusLabel on EvaluationStatus {
  String label(AppLocalizations l10n) => switch (this) {
    EvaluationStatus.notStarted => l10n.assignmentsStatusNotStarted,
    EvaluationStatus.inProgress => l10n.assignmentsStatusInProgress,
    EvaluationStatus.complete => l10n.assignmentsStatusComplete,
    EvaluationStatus.missing => l10n.assignmentsStatusMissing,
    EvaluationStatus.excused => l10n.assignmentsStatusExcused,
  };
}

extension RubricIssueLabel on RubricIssue {
  String label(AppLocalizations l10n) => switch (this) {
    RubricIssue.noTitle => l10n.assignmentsIssueNoTitle,
    RubricIssue.noGroups => l10n.assignmentsIssueNoGroups,
    RubricIssue.emptyGroup => l10n.assignmentsIssueEmptyGroup,
    RubricIssue.weightsNotHundred => l10n.assignmentsIssueWeights,
    RubricIssue.noLevels => l10n.assignmentsIssueNoLevels,
    RubricIssue.duplicateLevelPoints => l10n.assignmentsIssueDuplicateLevels,
  };
}

/// The status pill on a student row. The words carry the meaning; the fill
/// only reinforces it.
class StatusChip extends StatelessWidget {
  const new(this.status, {super.key});

  final EvaluationStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      EvaluationStatus.complete => (accent, secondary),
      EvaluationStatus.inProgress => (primaryLighter, secondary),
      EvaluationStatus.missing => (secondary, accent),
      EvaluationStatus.excused => (primaryDark, primaryLighter),
      EvaluationStatus.notStarted => (primaryDark, primaryLighter),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label(context.l10n),
        style: RubricTextStyles.caption.copyWith(color: fg, fontSize: 12),
      ),
    );
  }
}

/// A labelled input well: small hint above a large borderless field.
class FieldCard extends StatelessWidget {
  const new({required this.label, required this.child, this.help, super.key});

  final String label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Insets.card,
      decoration: BoxDecoration(color: primaryCard, borderRadius: Corners.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHint(label),
          const SizedBox(height: Insets.xs),
          child,
          if (help != null) ...[
            const SizedBox(height: Insets.xs),
            Text(help!, style: RubricTextStyles.caption),
          ],
        ],
      ),
    );
  }
}

/// Title, description, due date and points — shared by "New assignment" and
/// "Edit details". The parent owns the controllers and the due date.
class AssignmentDetailsFields extends StatelessWidget {
  const new({
    required this.title,
    required this.description,
    required this.points,
    required this.dueDate,
    required this.onDueDateChanged,
    this.autofocusTitle = false,
    super.key,
  });

  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController points;
  final DateTime? dueDate;
  final ValueChanged<DateTime?> onDueDateChanged;
  final bool autofocusTitle;

  Future<void> _pickDate(BuildContext context) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: dueDate ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onDueDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldCard(
          label: l10n.assignmentsTitleLabel,
          child: RubricTextField(
            key: const Key('assignments.title'),
            controller: title,
            hintText: l10n.assignmentsTitleHint,
            autofocus: autofocusTitle,
            textInputAction: TextInputAction.next,
            style: RubricTextStyles.cardTitle,
            hintStyle: RubricTextStyles.cardTitle.copyWith(
              color: primaryLighter,
            ),
          ),
        ),
        const SizedBox(height: Insets.md),
        FieldCard(
          label: l10n.assignmentsDescriptionLabel,
          child: RubricTextField(
            key: const Key('assignments.description'),
            controller: description,
            hintText: l10n.assignmentsDescriptionHint,
            maxLines: 4,
            minLines: 1,
            style: RubricTextStyles.bodySmall,
            hintStyle: RubricTextStyles.bodySmall,
          ),
        ),
        const SizedBox(height: Insets.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _DueDateCard(
                dueDate: dueDate,
                onPick: () => _pickDate(context),
                onClear: () => onDueDateChanged(null),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              flex: 2,
              child: FieldCard(
                label: l10n.assignmentsPointsLabel,
                child: RubricTextField(
                  key: const Key('assignments.points'),
                  controller: points,
                  hintText: '100',
                  semanticLabel: l10n.assignmentsPointsLabel,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                  ],
                  style: RubricTextStyles.cardTitle,
                  hintStyle: RubricTextStyles.cardTitle.copyWith(
                    color: primaryLighter,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.xs),
        Text(l10n.assignmentsPointsHelp, style: RubricTextStyles.caption),
      ],
    );
  }
}

class _DueDateCard extends StatelessWidget {
  const new({
    required this.dueDate,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? dueDate;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = dueDate == null
        ? l10n.assignmentsNoDueDate
        : formatDueDate(context, dueDate!);
    return Material(
      color: primaryCard,
      borderRadius: Corners.card,
      child: InkWell(
        borderRadius: Corners.card,
        onTap: onPick,
        child: Padding(
          padding: Insets.card.copyWith(right: Insets.xs),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: '${l10n.assignmentsDueLabel}: $text',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CardHint(l10n.assignmentsDueLabel),
                      const SizedBox(height: Insets.xs),
                      Text(
                        text,
                        key: const Key('assignments.due'),
                        style: RubricTextStyles.listTitle.copyWith(
                          color: dueDate == null ? primaryLighter : white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (dueDate != null)
                IconButton(
                  tooltip: l10n.assignmentsClearDueDate,
                  onPressed: onClear,
                  icon: const FaIcon(
                    FontAwesomeIcons.xmark,
                    color: primaryLighter,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Parses the points field; null when it is not a positive number.
double? parsePoints(String text) {
  final value = double.tryParse(text.trim());
  return value == null || value <= 0 ? null : value;
}

/// A tappable row in a [RubricSheet] action list.
class SheetAction extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    super.key,
  });

  final FaIconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? inactive
        : destructive
        ? accent
        : white;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: Corners.card,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              SizedBox(width: 36, child: FaIcon(icon, size: 18, color: color)),
              Expanded(
                child: Text(
                  label,
                  style: RubricTextStyles.listTitle.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
