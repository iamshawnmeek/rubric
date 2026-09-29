import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubric_builder/rubric_draft.dart';
import 'package:rubric/features/rubric_builder/rubric_draft_notifier.dart';
import 'package:rubric/features/rubric_builder/widgets/builder_widgets.dart';
import 'package:rubric/l10n/l10n.dart';

/// Step 4: Simple/Detailed, the letter-grade bands and — for detailed
/// rubrics — the performance levels and per-objective descriptors.
class ScaleStep extends ConsumerWidget {
  const new({required this.draft, required this.rubricId, super.key});

  final RubricDraft draft;
  final String rubricId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final notifier = ref.read(rubricDraftProvider(rubricId).notifier);
    final rubric = draft.rubric;
    final detailed = rubric.mode == GradingMode.detailed;
    final scaleProblem = draft.sortedScale.problem;
    final presets = {
      GradingScale.standard: l.builderPresetStandard,
      GradingScale.plusMinus: l.builderPresetPlusMinus,
      GradingScale.passFail: l.builderPresetPassFail,
    };

    return SliverList.list(
      children: [
        SegmentedToggle<GradingMode>(
          segments: {
            GradingMode.simple: l.gradingScaleToggleSimple,
            GradingMode.detailed: l.gradingScaleToggleDetailed,
          },
          selected: rubric.mode,
          onChanged: notifier.setMode,
        ),
        const SizedBox(height: Insets.md),
        Text(
          detailed ? l.builderModeDetailedMessage : l.builderModeSimpleMessage,
          style: RubricTextStyles.bodySmall,
        ),
        SectionLabel(l.builderLetterGrades),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final MapEntry(key: scale, value: label) in presets.entries)
              RubricChip(
                label: label,
                selected: draft.sortedScale == scale,
                onTap: () => notifier.applyScale(scale),
              ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        for (final (i, band) in rubric.scale.bands.indexed)
          _BandRow(
            key: ValueKey('band-$i'),
            band: band,
            upperBound: _upperBoundOf(band),
            canRemove: rubric.scale.bands.length > 1,
            onLetter: (v) => notifier.updateBand(i, letter: v),
            onMin: (v) => notifier.updateBand(i, min: v),
            onRemove: () => notifier.removeBand(i),
          ),
        const SizedBox(height: Insets.sm),
        DashedBox(
          label: l.builderAddGrade,
          height: 60,
          onTap: notifier.addBand,
        ),
        if (scaleProblem != null) ProblemNote(scaleProblem),
        if (detailed) ...[
          SectionLabel(l.builderLevels),
          Text(l.builderLevelsIntro, style: RubricTextStyles.bodySmall),
          const SizedBox(height: Insets.md),
          for (final (i, level) in rubric.levels.indexed)
            _LevelRow(
              key: ValueKey(level.id),
              level: level,
              isFirst: i == 0,
              isLast: i == rubric.levels.length - 1,
              rubricId: rubricId,
            ),
          const SizedBox(height: Insets.sm),
          DashedBox(
            label: l.builderAddLevel,
            height: 60,
            onTap: () => notifier.addLevel(l.builderNewLevelLabel),
          ),
          if (rubric.issues.contains(RubricIssue.noLevels))
            ProblemNote(l.builderIssueNoLevels),
          if (rubric.issues.contains(RubricIssue.duplicateLevelPoints))
            ProblemNote(l.builderIssueDuplicatePoints),
          if (rubric.levels.isNotEmpty && draft.objectives.isNotEmpty) ...[
            SectionLabel(l.builderDescriptors),
            Text(l.builderDescriptorsIntro, style: RubricTextStyles.bodySmall),
            const SizedBox(height: Insets.md),
            for (final (i, objective) in draft.objectives.indexed)
              _DescriptorCard(
                key: ValueKey('descriptors-${objective.id}'),
                number: i + 1,
                objective: objective,
                levels: rubric.levels,
                rubricId: rubricId,
              ),
          ],
        ],
      ],
    );
  }

  /// The "to" value beside a band, from its place in the sorted scale.
  double _upperBoundOf(LetterBand band) {
    final sorted = draft.sortedScale;
    final index = sorted.bands.indexOf(band);
    return index < 0 ? 100 : sorted.upperBoundOf(index);
  }
}

/// v1's grade row: letter, minimum "to" upper bound.
class _BandRow extends StatelessWidget {
  const new({
    required this.band,
    required this.upperBound,
    required this.canRemove,
    required this.onLetter,
    required this.onMin,
    required this.onRemove,
    super.key,
  });

  final LetterBand band;
  final double upperBound;
  final bool canRemove;
  final ValueChanged<String> onLetter;
  final ValueChanged<double> onMin;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const style = RubricTextStyles.gradingScaleInput;
    final name = band.letter.trim().isEmpty
        ? l.builderGradeNameHint
        : band.letter;

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Row(
        children: [
          FieldBox(
            width: 76,
            child: DraftField(
              value: band.letter,
              hintText: l.builderGradeNameHint,
              semanticLabel: l.builderGradeNameLabel,
              style: style.copyWith(color: white),
              hintStyle: style,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              onChanged: onLetter,
            ),
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: FieldBox(
              child: DraftField(
                value: formatNumber(band.min),
                hintText: '0',
                semanticLabel: l.builderGradeMinLabel(name),
                style: style.copyWith(color: white),
                hintStyle: style,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: decimalInput,
                textInputAction: TextInputAction.next,
                onChanged: (v) {
                  final min = double.tryParse(v);
                  if (min != null) onMin(min);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
            child: BodyGradingScaleInput(l.gradingScaleTo),
          ),
          Expanded(
            child: Semantics(
              label: l.builderGradeMaxLabel(name, formatNumber(upperBound)),
              excludeSemantics: true,
              child: FieldBox(
                child: BodyGradingScaleInput(formatNumber(upperBound)),
              ),
            ),
          ),
          BuilderIconButton(
            icon: FontAwesomeIcons.xmark,
            label: l.builderRemoveGrade(name),
            onTap: canRemove ? onRemove : null,
          ),
        ],
      ),
    );
  }
}

enum _LevelAction { up, down, remove }

class _LevelRow extends ConsumerWidget {
  const new({
    required this.level,
    required this.isFirst,
    required this.isLast,
    required this.rubricId,
    super.key,
  });

  final PerformanceLevel level;
  final bool isFirst;
  final bool isLast;
  final String rubricId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final notifier = ref.read(rubricDraftProvider(rubricId).notifier);
    const style = RubricTextStyles.gradingScaleInput;
    final name = level.label.trim().isEmpty
        ? l.builderLevelLabelHint
        : level.label;

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Row(
        children: [
          Expanded(
            child: FieldBox(
              child: DraftField(
                value: level.label,
                hintText: l.builderLevelLabelHint,
                semanticLabel: l.builderLevelLabelHint,
                style: style.copyWith(color: white),
                hintStyle: style,
                textInputAction: TextInputAction.next,
                onChanged: (v) => notifier.updateLevel(level.id, label: v),
              ),
            ),
          ),
          const SizedBox(width: Insets.sm),
          FieldBox(
            width: 84,
            child: Row(
              children: [
                Expanded(
                  child: DraftField(
                    value: formatNumber(level.points),
                    hintText: '0',
                    semanticLabel: l.builderLevelPointsLabel(name),
                    style: style.copyWith(color: white),
                    hintStyle: style,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: decimalInput,
                    onChanged: (v) {
                      final points = double.tryParse(v);
                      if (points != null) {
                        notifier.updateLevel(level.id, points: points);
                      }
                    },
                  ),
                ),
                Text(l.builderPointsSuffix, style: RubricTextStyles.caption),
              ],
            ),
          ),
          PopupMenuButton<_LevelAction>(
            tooltip: l.builderLevelActions(name),
            icon: const FaIcon(
              FontAwesomeIcons.ellipsisVertical,
              color: primaryLighter,
              size: 18,
            ),
            onSelected: (action) => switch (action) {
              _LevelAction.up => notifier.moveLevel(level.id, -1),
              _LevelAction.down => notifier.moveLevel(level.id, 1),
              _LevelAction.remove => notifier.removeLevel(level.id),
            },
            itemBuilder: (context) => [
              if (!isFirst)
                PopupMenuItem(
                  value: _LevelAction.up,
                  child: Text(l.builderMoveUp),
                ),
              if (!isLast)
                PopupMenuItem(
                  value: _LevelAction.down,
                  child: Text(l.builderMoveDown),
                ),
              PopupMenuItem(
                value: _LevelAction.remove,
                child: Text(l.builderRemove),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One objective's row of the objective × level descriptor grid.
class _DescriptorCard extends ConsumerWidget {
  const new({
    required this.number,
    required this.objective,
    required this.levels,
    required this.rubricId,
    super.key,
  });

  final int number;
  final Objective objective;
  final List<PerformanceLevel> levels;
  final String rubricId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final notifier = ref.read(rubricDraftProvider(rubricId).notifier);

    return Container(
      margin: const EdgeInsets.only(bottom: Insets.md),
      padding: Insets.card,
      decoration: BoxDecoration(color: primaryCard, borderRadius: Corners.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHint(l.builderObjectiveHint(number)),
          const SizedBox(height: Insets.xs),
          CardTitle(objective.title),
          for (final level in levels) ...[
            const SizedBox(height: Insets.md),
            Text(
              l.builderLevelWithPoints(level.label, formatNumber(level.points)),
              style: RubricTextStyles.caption,
            ),
            const SizedBox(height: Insets.xs),
            Container(
              padding: const EdgeInsets.all(Insets.sm),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: Corners.card,
              ),
              constraints: const BoxConstraints(minHeight: Sizes.minTap),
              alignment: Alignment.centerLeft,
              child: DraftField(
                key: ValueKey('${objective.id}-${level.id}'),
                value: objective.descriptors[level.id] ?? '',
                hintText: l.builderDescriptorHint(level.label),
                semanticLabel: l.builderDescriptorLabel(
                  objective.title,
                  level.label,
                ),
                style: RubricTextStyles.bodySmall,
                maxLines: null,
                onChanged: (v) =>
                    notifier.setDescriptor(objective.id, level.id, v),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
