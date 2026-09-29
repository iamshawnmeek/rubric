import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubrics/library_filter.dart';
import 'package:rubric/features/rubrics/rubric_labels.dart';
import 'package:rubric/l10n/l10n.dart';

/// A read-only rendering of a whole rubric: summary, groups with weight bars,
/// objectives, the level ladder and descriptor grid (detailed mode) and the
/// grading scale. Used by the detail page and the template preview.
class RubricOverview extends StatelessWidget {
  const new({required this.rubric, this.usage, super.key});

  final Rubric rubric;

  /// How many assignments use this rubric; null hides the line (templates).
  final int? usage;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final detailed = rubric.mode == GradingMode.detailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rubric.description.trim().isNotEmpty) ...[
          Text(rubric.description, style: RubricTextStyles.bodySmall),
          const SizedBox(height: Insets.lg),
        ],
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: '${rubric.groups.length}',
                label: l.rubricsStatGroups,
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: StatTile(
                value: '${rubric.objectives.length}',
                label: l.rubricsStatObjectives,
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: StatTile(
                value: l.modeLabel(rubric.mode),
                label: l.rubricsStatMode,
              ),
            ),
          ],
        ),
        if (usage != null) ...[
          const SizedBox(height: Insets.sm),
          _UsageLine(count: usage!),
        ],
        if (!rubric.isReady) ...[
          const SizedBox(height: Insets.md),
          _IssuesCard(issues: rubric.issues),
        ],
        if (rubric.groups.isNotEmpty) ...[
          SectionLabel(l.rubricsWeightsSection),
          _WeightStrip(groups: rubric.groups),
          for (final (i, group) in rubric.groups.indexed) ...[
            const SizedBox(height: Insets.sm),
            _GroupCard(group: group, color: seriesRamp[i % seriesRamp.length]),
          ],
        ],
        if (detailed && rubric.levels.isNotEmpty) ...[
          SectionLabel(l.rubricsLevelsSection),
          _LevelLadder(levels: rubric.levels),
          if (rubric.objectives.isNotEmpty) ...[
            SectionLabel(l.rubricsDescriptorsSection),
            _DescriptorGrid(rubric: rubric),
          ],
        ],
        SectionLabel(l.rubricsScaleSection),
        _ScaleTable(rubric: rubric),
      ],
    );
  }
}

class _UsageLine extends StatelessWidget {
  const new({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const FaIcon(
          FontAwesomeIcons.clipboardCheck,
          size: 14,
          color: primaryLight,
        ),
        const SizedBox(width: Insets.xs),
        Expanded(
          child: Text(
            context.l10n.rubricsUsedIn(count),
            style: RubricTextStyles.caption,
          ),
        ),
      ],
    );
  }
}

class _IssuesCard extends StatelessWidget {
  const new({required this.issues});

  final List<RubricIssue> issues;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      padding: Insets.card,
      decoration: BoxDecoration(
        color: primaryDark,
        borderRadius: Corners.card,
        border: Border.all(color: accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.triangleExclamation,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  l.rubricsDraftTitle,
                  style: RubricTextStyles.listTitle.copyWith(fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.xs),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '•  ${l.issueLabel(issue)}',
                style: RubricTextStyles.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Every group's share of the grade as one segmented bar. The group cards
/// below repeat each weight as text, so no information rides on color alone.
class _WeightStrip extends StatelessWidget {
  const new({required this.groups});

  final List<RubricGroup> groups;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final summary = [
      for (final g in groups) '${g.title} ${l.rubricsWeightPercent(g.weight)}',
    ].join(', ');
    return Semantics(
      label: l.rubricsWeightsSemantics(summary),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: Corners.card,
        child: SizedBox(
          height: 14,
          child: Row(
            children: [
              for (final (i, g) in groups.indexed)
                if (g.weight > 0)
                  Expanded(
                    flex: g.weight,
                    child: Container(
                      margin: EdgeInsets.only(
                        right: i == groups.length - 1 ? 0 : 2,
                      ),
                      color: seriesRamp[i % seriesRamp.length],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const new({required this.group, required this.color});

  final RubricGroup group;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Insets.card,
      decoration: BoxDecoration(color: primaryCard, borderRadius: Corners.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: CardTitle(group.title, fontSize: 22)),
              const SizedBox(width: Insets.sm),
              Text(
                context.l10n.rubricsWeightPercent(group.weight),
                style: RubricTextStyles.statValue.copyWith(fontSize: 26),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          ExcludeSemantics(
            child: RubricProgressBar(value: group.weight / 100, color: color),
          ),
          for (final objective in group.objectives)
            Padding(
              padding: const EdgeInsets.only(top: Insets.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7, right: Insets.sm),
                    child: FaIcon(
                      FontAwesomeIcons.solidCircle,
                      size: 6,
                      color: primaryLighter,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          objective.title,
                          style: RubricTextStyles.listTitle.copyWith(
                            fontSize: 18,
                          ),
                        ),
                        if (objective.description.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              objective.description,
                              style: RubricTextStyles.caption.copyWith(
                                color: primaryLighter,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The detailed-mode ladder, best level first.
class _LevelLadder extends StatelessWidget {
  const new({required this.levels});

  final List<PerformanceLevel> levels;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: [
        for (final level in levels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: primaryDark,
              borderRadius: Corners.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  level.label,
                  style: RubricTextStyles.listTitle.copyWith(fontSize: 18),
                ),
                Text(
                  l.rubricsLevelPoints(formatNumber(level.points)),
                  style: RubricTextStyles.caption,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Objectives down, levels across. Scrolls sideways on phones rather than
/// crushing the descriptors into unreadable columns.
class _DescriptorGrid extends StatelessWidget {
  const new({required this.rubric});

  final Rubric rubric;

  static const _objectiveWidth = 170.0;
  static const _levelWidth = 210.0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    Widget cell(Widget child, {Color? color}) => Container(
      color: color,
      padding: const EdgeInsets.all(Insets.sm),
      child: child,
    );

    final header = TableRow(
      decoration: const BoxDecoration(color: primaryDark),
      children: [
        cell(
          Text(
            l.rubricsDescriptorObjective.toUpperCase(),
            style: RubricTextStyles.sectionLabel,
          ),
        ),
        for (final level in rubric.levels)
          cell(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level.label, style: RubricTextStyles.listTitle),
                Text(
                  l.rubricsLevelPoints(formatNumber(level.points)),
                  style: RubricTextStyles.caption,
                ),
              ],
            ),
          ),
      ],
    );

    final rows = <TableRow>[
      for (final group in rubric.groups)
        for (final objective in group.objectives)
          TableRow(
            decoration: const BoxDecoration(color: primaryCard),
            children: [
              cell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.title, style: RubricTextStyles.caption),
                    const SizedBox(height: 2),
                    Text(
                      objective.title,
                      style: RubricTextStyles.listTitle.copyWith(fontSize: 17),
                    ),
                  ],
                ),
              ),
              for (final level in rubric.levels)
                cell(switch (objective.descriptors[level.id]?.trim()) {
                  final text? when text.isNotEmpty => Text(
                    text,
                    style: RubricTextStyles.bodySmall.copyWith(
                      fontSize: 15,
                      color: white,
                    ),
                  ),
                  _ => Text(
                    l.rubricsDescriptorMissing,
                    style: RubricTextStyles.caption.copyWith(color: inactive),
                  ),
                }),
            ],
          ),
    ];

    return ClipRRect(
      borderRadius: Corners.card,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          columnWidths: {
            0: const FixedColumnWidth(_objectiveWidth),
            for (var i = 0; i < rubric.levels.length; i++)
              i + 1: const FixedColumnWidth(_levelWidth),
          },
          border: const TableBorder(
            horizontalInside: BorderSide(color: secondary, width: 2),
            verticalInside: BorderSide(color: secondary, width: 2),
          ),
          children: [header, ...rows],
        ),
      ),
    );
  }
}

class _ScaleTable extends StatelessWidget {
  const new({required this.rubric});

  final Rubric rubric;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final bands = rubric.scale.bands;
    return Container(
      decoration: BoxDecoration(color: primaryCard, borderRadius: Corners.card),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Column(
        children: [
          for (final (i, band) in bands.indexed) ...[
            if (i > 0) const Divider(height: 1, color: primaryDark),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              child: Row(
                children: [
                  Expanded(child: CardTitle(band.letter, fontSize: 22)),
                  Text(
                    l.rubricsScaleRange(
                      formatNumber(band.min),
                      formatNumber(rubric.scale.upperBoundOf(i)),
                    ),
                    style: RubricTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
