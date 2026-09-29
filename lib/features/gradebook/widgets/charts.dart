import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/gradebook/gradebook_model.dart';
import 'package:rubric/features/gradebook/widgets/grade_visuals.dart';
import 'package:rubric/l10n/l10n.dart';

const _chartHeight = 190.0;

Widget _axisLabel(String text, TitleMeta meta) => SideTitleWidget(
  meta: meta,
  child: Text(text, style: RubricTextStyles.caption.copyWith(fontSize: 11)),
);

FlGridData get _grid => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: 25,
  getDrawingHorizontalLine: (_) =>
      FlLine(color: secondary.withValues(alpha: .6), strokeWidth: 1),
);

/// Bars for [histogram] counts over 0–100, each tinted by its grade tier.
class ScoreHistogram extends StatelessWidget {
  const new({required this.counts, super.key});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = 100 ~/ counts.length;
    final top = math.max(1, counts.fold(0, math.max));
    final description = [
      for (var i = 0; i < counts.length; i++)
        l10n.gradebookHistogramBucket(
          i * width,
          i == counts.length - 1 ? 100 : (i + 1) * width - 1,
          counts[i],
        ),
    ].join(', ');

    return Semantics(
      label: l10n.gradebookChartSemantics(
        l10n.gradebookDistributionTitle,
        description,
      ),
      excludeSemantics: true,
      child: SizedBox(
        height: _chartHeight,
        child: BarChart(
          BarChartData(
            maxY: top.toDouble(),
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: math.max(1, (top / 4).ceilToDouble()),
              getDrawingHorizontalLine: (_) => FlLine(
                color: secondary.withValues(alpha: .6),
                strokeWidth: 1,
              ),
            ),
            barTouchData: const BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: math.max(1, (top / 4).ceilToDouble()),
                  getTitlesWidget: (v, meta) =>
                      _axisLabel(v.toInt().toString(), meta),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (v, meta) =>
                      _axisLabel('${v.toInt() * width}', meta),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < counts.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: counts[i].toDouble(),
                      width: 16,
                      color: tierTone(gradeTier(i * width.toDouble()))
                          .background,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line on a [GradeTrendChart].
class TrendSeries {
  const new({
    required this.label,
    required this.points,
    required this.color,
    this.dashed = false,
  });

  final String label;

  /// x is the assignment's position in the course timeline.
  final List<(int, double)> points;
  final Color color;
  final bool dashed;
}

/// Grades over the course timeline, 0–100 on the y axis. [xLabels] names
/// each x position (a short due date).
class GradeTrendChart extends StatelessWidget {
  const new({
    required this.title,
    required this.series,
    required this.xLabels,
    super.key,
  });

  final String title;
  final List<TrendSeries> series;
  final List<String> xLabels;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lastX = math.max(1, xLabels.length - 1).toDouble();
    final labelEvery = math.max(1, (xLabels.length / 5).ceil());
    final description = [
      for (final s in series)
        '${s.label}: ${[for (final (x, y) in s.points) l10n.gradebookChartPoint(xLabels[x], formatPercent(y))].join(', ')}',
    ].join('. ');

    return Semantics(
      label: l10n.gradebookChartSemantics(title, description),
      excludeSemantics: true,
      child: SizedBox(
        height: _chartHeight,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: 100,
            minX: 0,
            maxX: lastX,
            borderData: FlBorderData(show: false),
            gridData: _grid,
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => secondary,
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      formatPercent(s.y),
                      RubricTextStyles.caption.copyWith(color: s.bar.color),
                    ),
                ],
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: 25,
                  getTitlesWidget: (v, meta) =>
                      _axisLabel(v.toInt().toString(), meta),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: 1,
                  getTitlesWidget: (v, meta) {
                    final i = v.round();
                    if (v != i || i >= xLabels.length || i % labelEvery != 0) {
                      return const SizedBox.shrink();
                    }
                    return _axisLabel(xLabels[i], meta);
                  },
                ),
              ),
            ),
            lineBarsData: [
              for (final s in series)
                LineChartBarData(
                  spots: [
                    for (final (x, y) in s.points) FlSpot(x.toDouble(), y),
                  ],
                  color: s.color,
                  barWidth: 3,
                  dashArray: s.dashed ? const [6, 4] : null,
                  dotData: FlDotData(
                    getDotPainter: (spot, _, bar, _) => FlDotCirclePainter(
                      radius: 4,
                      color: bar.color ?? accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A key for a multi-series chart: swatch and name, so lines are told apart
/// by label as well as color.
class SeriesKey extends StatelessWidget {
  const new({required this.series, super.key});

  final List<TrendSeries> series;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Insets.md,
      children: [
        for (final s in series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 18, height: 3, color: s.color),
              const SizedBox(width: 6),
              Text(
                s.dashed ? '${s.label} (- -)' : s.label,
                style: RubricTextStyles.caption,
              ),
            ],
          ),
      ],
    );
  }
}

/// One bar per letter, labelled with the letter and the count.
class LetterBars extends StatelessWidget {
  const new({required this.counts, super.key});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    return Column(
      children: [
        for (final (i, e) in counts.entries.indexed)
          Semantics(
            label: '${e.key}: ${context.l10n.gradebookLetterCount(e.value)}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(e.key, style: RubricTextStyles.listTitle),
                  ),
                  Expanded(
                    child: RubricProgressBar(
                      value: total == 0 ? 0 : e.value / total,
                      height: 10,
                      color: seriesRamp[i % seriesRamp.length],
                      track: secondary,
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${e.value}',
                      textAlign: TextAlign.end,
                      style: RubricTextStyles.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
