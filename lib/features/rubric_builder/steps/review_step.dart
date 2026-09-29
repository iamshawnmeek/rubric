import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubric_builder/rubric_builder_page.dart';
import 'package:rubric/features/rubric_builder/rubric_draft.dart';
import 'package:rubric/features/rubric_builder/rubric_draft_notifier.dart';
import 'package:rubric/features/rubric_builder/widgets/builder_widgets.dart';
import 'package:rubric/l10n/l10n.dart';

/// Something standing between the draft and a save, and where to fix it.
typedef DraftFix = ({String message, BuilderStep step});

/// Every blocking problem with [draft], phrased for a teacher.
List<DraftFix> draftFixes(RubricDraft draft, AppLocalizations l) {
  final rubric = draft.rubric;
  final issues = rubric.issues;
  final scaleProblem = draft.sortedScale.problem;
  return [
    if (draft.objectives.isEmpty)
      (message: l.builderIssueNoObjectives, step: BuilderStep.objectives),
    if (draft.ungrouped.isNotEmpty)
      (
        message: l.builderIssueUngrouped(draft.ungrouped.length),
        step: BuilderStep.groups,
      ),
    if (draft.objectives.isNotEmpty && issues.contains(RubricIssue.noGroups))
      (message: l.builderIssueNoGroups, step: BuilderStep.groups),
    if (issues.contains(RubricIssue.emptyGroup))
      (message: l.builderIssueEmptyGroup, step: BuilderStep.groups),
    if (rubric.groups.any((g) => g.title.trim().isEmpty))
      (message: l.builderIssueUntitledGroup, step: BuilderStep.groups),
    if (issues.contains(RubricIssue.weightsNotHundred))
      (
        message: l.builderIssueWeights(rubric.totalWeight),
        step: BuilderStep.weights,
      ),
    if (scaleProblem != null) (message: scaleProblem, step: BuilderStep.scale),
    if (issues.contains(RubricIssue.noLevels))
      (message: l.builderIssueNoLevels, step: BuilderStep.scale),
    if (issues.contains(RubricIssue.duplicateLevelPoints))
      (message: l.builderIssueDuplicatePoints, step: BuilderStep.scale),
    if (issues.contains(RubricIssue.noTitle))
      (message: l.builderIssueNoTitle, step: BuilderStep.review),
  ];
}

/// Step 5: name the rubric, check it over, fix anything flagged, save.
class ReviewStep extends ConsumerWidget {
  const new({
    required this.draft,
    required this.rubricId,
    required this.titleFocus,
    required this.onFix,
    super.key,
  });

  final RubricDraft draft;
  final String rubricId;
  final FocusNode titleFocus;
  final ValueChanged<BuilderStep> onFix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final notifier = ref.read(rubricDraftProvider(rubricId).notifier);
    final rubric = draft.rubric;
    final fixes = draftFixes(draft, l);

    return SliverList.list(
      children: [
        RubricFormWell(
          child: DraftField(
            value: rubric.title,
            hintText: l.builderTitleHint,
            semanticLabel: l.builderTitleLabel,
            focusNode: titleFocus,
            style: RubricTextStyles.cardTitle,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => notifier.setDetails(title: v),
          ),
        ),
        const SizedBox(height: Insets.md),
        RubricFormWell(
          child: DraftField(
            value: rubric.subject,
            hintText: l.builderSubjectHint,
            style: RubricTextStyles.bodySmall,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => notifier.setDetails(subject: v),
          ),
        ),
        const SizedBox(height: Insets.md),
        RubricFormWell(
          child: DraftField(
            value: rubric.description,
            hintText: l.builderDescriptionHint,
            style: RubricTextStyles.bodySmall,
            maxLines: 5,
            minLines: 2,
            onChanged: (v) => notifier.setDetails(description: v),
          ),
        ),
        if (fixes.isNotEmpty) ...[
          SectionLabel(l.builderFixesTitle),
          for (final fix in fixes)
            _FixCard(
              fix: fix,
              onTap: () => fix.step == BuilderStep.review
                  ? titleFocus.requestFocus()
                  : onFix(fix.step),
            ),
        ],
        SectionLabel(l.builderPreviewTitle),
        RubricPreview(draft: draft),
      ],
    );
  }
}

class _FixCard extends StatelessWidget {
  const new({required this.fix, required this.onTap});

  final DraftFix fix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Semantics(
        button: true,
        label: '${fix.message} ${l.builderFix}',
        excludeSemantics: true,
        child: Material(
          color: primaryDark,
          borderRadius: Corners.card,
          child: InkWell(
            borderRadius: Corners.card,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.md,
                vertical: Insets.sm,
              ),
              child: Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.circleExclamation,
                    color: accent,
                    size: 18,
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Text(
                      fix.message,
                      style: RubricTextStyles.bodySmall.copyWith(color: white),
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: Sizes.minTap),
                    child: Center(
                      child: Text(
                        l.builderFix,
                        style: RubricTextStyles.button.copyWith(color: accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A read-only rendering of the whole rubric: groups with weights, their
/// objectives (and descriptors in detailed mode), the levels and the scale.
class RubricPreview extends StatelessWidget {
  const new({required this.draft, super.key});

  final RubricDraft draft;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rubric = draft.rubric;
    final detailed = rubric.mode == GradingMode.detailed;
    final numbers = {
      for (final (i, o) in draft.objectives.indexed) o.id: i + 1,
    };
    final scale = draft.sortedScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          rubric.title.trim().isEmpty ? l.builderUntitledRubric : rubric.title,
          style: RubricTextStyles.bodyOne,
        ),
        if (rubric.subject.trim().isNotEmpty)
          Text(rubric.subject, style: RubricTextStyles.cardHint),
        if (rubric.description.trim().isNotEmpty) ...[
          const SizedBox(height: Insets.xs),
          Text(rubric.description, style: RubricTextStyles.bodySmall),
        ],
        const SizedBox(height: Insets.md),
        Text(
          detailed ? l.gradingScaleToggleDetailed : l.gradingScaleToggleSimple,
          style: RubricTextStyles.caption,
        ),
        const SizedBox(height: Insets.md),
        for (final group in rubric.groups)
          Container(
            margin: const EdgeInsets.only(bottom: Insets.md),
            padding: Insets.card,
            decoration: BoxDecoration(
              color: primaryCard,
              borderRadius: Corners.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: CardTitle(
                        group.title.trim().isEmpty
                            ? l.builderUntitledGroup
                            : group.title,
                      ),
                    ),
                    CardTitle(l.builderPercent(group.weight), color: accent),
                  ],
                ),
                for (final objective in group.objectives) ...[
                  const SizedBox(height: Insets.md),
                  CardHint(
                    l.builderObjectiveHint(numbers[objective.id] ?? 0),
                    fontSize: 14,
                  ),
                  Text(objective.title, style: RubricTextStyles.listTitle),
                  if (objective.description.isNotEmpty)
                    Text(
                      objective.description,
                      style: RubricTextStyles.bodySmall,
                    ),
                  if (detailed)
                    for (final level in rubric.levels)
                      if ((objective.descriptors[level.id] ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${level.label}: ${objective.descriptors[level.id]}',
                            style: RubricTextStyles.caption,
                          ),
                        ),
                ],
              ],
            ),
          ),
        if (draft.ungrouped.isNotEmpty)
          Text(
            l.builderIssueUngrouped(draft.ungrouped.length),
            style: RubricTextStyles.bodySmall,
          ),
        if (detailed && rubric.levels.isNotEmpty) ...[
          SectionLabel(l.builderLevels),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final level in rubric.levels)
                RubricChip(
                  label: l.builderLevelWithPoints(
                    level.label,
                    formatNumber(level.points),
                  ),
                ),
            ],
          ),
        ],
        SectionLabel(l.builderLetterGrades),
        for (final (i, band) in scale.bands.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(band.letter, style: RubricTextStyles.listTitle),
                ),
                Text(
                  l.builderPreviewRange(
                    formatNumber(band.min),
                    formatNumber(scale.upperBoundOf(i)),
                  ),
                  style: RubricTextStyles.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
