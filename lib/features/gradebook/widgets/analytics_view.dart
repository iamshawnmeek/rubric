import 'package:flutter/material.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/gradebook/gradebook_model.dart';
import 'package:rubric/features/gradebook/widgets/charts.dart';
import 'package:rubric/features/gradebook/widgets/grade_visuals.dart';
import 'package:rubric/l10n/l10n.dart';

/// The analytics tab: headline numbers, score and letter distributions, the
/// class trend, objective mastery and who needs attention.
class AnalyticsView extends StatefulWidget {
  const new({required this.gradebook, required this.onStudentTap, super.key});

  final Gradebook gradebook;
  final void Function(Student student) onStudentTap;

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  /// Null shows course averages; otherwise one assignment's grades.
  String? _assignmentId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gb = widget.gradebook;
    final entered = gb.rows.fold(0, (n, r) => n + r.gradedCount);
    if (entered == 0) {
      return EmptyState(
        title: l10n.gradebookAnalyticsEmptyTitle,
        message: l10n.gradebookAnalyticsEmptyMessage,
      );
    }

    final selected = gb.assignments
        .where((a) => a.id == _assignmentId)
        .firstOrNull;
    final values = selected == null
        ? gb.studentAverages
        : gb.column(selected.id).map((c) => c.percent).whereType<double>();
    final scale = selected?.rubric.scale ?? gb.scale;
    final classAverage = gb.classAverage;
    final missing = gb.rows.fold(0, (n, r) => n + r.missingCount);
    final trend = gb.classTrend;
    final attention = needsAttention(gb);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _Tile(
                value: classAverage == null
                    ? '—'
                    : '${formatPercent(classAverage, decimals: 0)} '
                          '${gb.letterFor(classAverage)}',
                label: l10n.gradebookClassAverage,
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: _Tile(
                value: '$entered',
                label: l10n.gradebookGradesEntered,
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: _Tile(
                value: '$missing',
                label: l10n.gradebookMissingTotal,
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              RubricChip(
                label: l10n.gradebookDistributionAll,
                selected: selected == null,
                onTap: () => setState(() => _assignmentId = null),
              ),
              for (final a in gb.assignments) ...[
                const SizedBox(width: Insets.xs),
                RubricChip(
                  label: a.title,
                  selected: a.id == selected?.id,
                  onTap: () => setState(() => _assignmentId = a.id),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
        AnalyticsPanel(
          title: l10n.gradebookDistributionTitle,
          trailing: Text(
            selected?.title ?? l10n.gradebookDistributionAll,
            style: RubricTextStyles.caption,
          ),
          child: ScoreHistogram(counts: histogram(values)),
        ),
        AnalyticsPanel(
          title: l10n.gradebookLettersTitle,
          child: LetterBars(counts: letterDistribution(values, scale)),
        ),
        if (trend.isNotEmpty)
          AnalyticsPanel(
            title: l10n.gradebookTrendTitle,
            child: GradeTrendChart(
              title: l10n.gradebookTrendTitle,
              xLabels: [
                for (final a in gb.assignments)
                  shortDate(context, assignmentDate(a)),
              ],
              series: [
                TrendSeries(
                  label: l10n.gradebookClassMean,
                  color: accent,
                  points: [
                    for (final p in trend)
                      (gb.assignments.indexOf(p.assignment), p.percent),
                  ],
                ),
              ],
            ),
          ),
        AnalyticsPanel(
          title: l10n.gradebookMasteryTitle,
          child: MasteryHeatMap(gradebook: gb),
        ),
        SectionLabel(l10n.gradebookAttentionTitle),
        if (attention.isEmpty)
          Text(l10n.gradebookAttentionNone, style: RubricTextStyles.bodySmall)
        else
          for (final item in attention)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: RubricCard(
                cardHintText: [
                  if (item.missing > 0)
                    l10n.gradebookAttentionMissing(item.missing),
                  if (item.drop case final drop?)
                    l10n.gradebookAttentionDrop(drop.toStringAsFixed(0)),
                ].join(' · '),
                cardTitleText: item.row.student.displayName,
                titleMaxLines: 1,
                onTap: () => widget.onStudentTap(item.row.student),
                trailing: GradeBadge(
                  percent: item.row.average,
                  letter: gb.letterFor(item.row.average),
                  letters: false,
                ),
              ),
            ),
      ],
    );
  }
}

/// Objectives down, assignments across; each cell is the class mean on that
/// objective, tinted by tier and printed.
class MasteryHeatMap extends StatelessWidget {
  const new({required this.gradebook, super.key});

  final Gradebook gradebook;

  static const _labelWidth = 128.0;
  static const _cellWidth = 64.0;
  static const _cellHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mastery = objectiveMastery(gradebook);
    if (mastery.every((m) => m.overall == null)) {
      return Text(
        l10n.gradebookMasteryEmpty,
        style: RubricTextStyles.bodySmall,
      );
    }
    final assignments = gradebook.assignments;

    Widget cell(String objective, String column, double? value) => Semantics(
      label: l10n.gradebookMasteryCellSemantics(
        objective,
        column,
        formatPercent(value),
      ),
      excludeSemantics: true,
      child: Container(
        width: _cellWidth - 4,
        height: _cellHeight - 4,
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: value == null
              ? secondary
              : tierTone(gradeTier(value)).background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          value == null ? '—' : formatPercent(value, decimals: 0),
          style: RubricTextStyles.caption.copyWith(
            fontFamily: Fonts.black,
            color: value == null
                ? primaryLight
                : tierTone(gradeTier(value)).foreground,
          ),
        ),
      ),
    );

    Widget header(String text) => SizedBox(
      width: _cellWidth,
      height: _cellHeight,
      child: Center(
        child: Text(
          text,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: RubricTextStyles.caption.copyWith(fontSize: 11, height: 1.1),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _labelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: _cellHeight),
                  for (final m in mastery)
                    SizedBox(
                      height: _cellHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          m.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: RubricTextStyles.caption.copyWith(
                            color: white,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  children: [
                    Row(
                      children: [
                        header(l10n.gradebookMasteryOverall),
                        for (final a in assignments) header(a.title),
                      ],
                    ),
                    for (final m in mastery)
                      Row(
                        children: [
                          cell(
                            m.title,
                            l10n.gradebookMasteryOverall,
                            m.overall,
                          ),
                          for (final a in assignments)
                            if (m.means.containsKey(a.id))
                              cell(m.title, a.title, m.means[a.id])
                            else
                              const SizedBox(
                                width: _cellWidth,
                                height: _cellHeight,
                              ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.md),
        const TierLegend(),
      ],
    );
  }
}

/// A [StatTile] read as its own stop by screen readers rather than merged
/// with its neighbours.
class _Tile extends StatelessWidget {
  const new({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: StatTile(value: value, label: label),
  );
}
