import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/gradebook/gradebook_model.dart';
import 'package:rubric/l10n/l10n.dart';

/// Surface and text colors for a [gradeTier], drawn from [seriesRamp] so the
/// grid, heat-map and histogram share one key. Color is never the only cue:
/// every tinted surface also prints its number.
({Color background, Color foreground}) tierTone(int tier) => switch (tier) {
  4 => (background: seriesRamp[0], foreground: secondary),
  3 => (background: seriesRamp[1], foreground: secondary),
  2 => (background: seriesRamp[2], foreground: secondary),
  1 => (background: seriesRamp[3], foreground: white),
  _ => (background: seriesRamp[4], foreground: secondary),
};

/// The tier bounds [gradeTier] uses, highest first, as legend labels.
List<(int, String)> tierLegend(BuildContext context) {
  final l10n = context.l10n;
  return [
    (4, l10n.gradebookTierAtLeast(90)),
    (3, l10n.gradebookTierRange(80, 89)),
    (2, l10n.gradebookTierRange(70, 79)),
    (1, l10n.gradebookTierRange(60, 69)),
    (0, l10n.gradebookTierBelow(60)),
  ];
}

/// A row of swatches, each labelled with its range.
class TierLegend extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.xs,
      children: [
        for (final (tier, label) in tierLegend(context))
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: tierTone(tier).background,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(label, style: RubricTextStyles.caption),
            ],
          ),
      ],
    );
  }
}

String statusLabel(BuildContext context, CellStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    CellStatus.graded => l10n.gradebookStatusGraded,
    CellStatus.inProgress => l10n.gradebookStatusInProgress,
    CellStatus.missing => l10n.gradebookStatusMissing,
    CellStatus.excused => l10n.gradebookStatusExcused,
    CellStatus.notGraded => l10n.gradebookStatusNotGraded,
  };
}

FaIconData? statusGlyph(CellStatus status) => switch (status) {
  CellStatus.missing => FontAwesomeIcons.triangleExclamation,
  CellStatus.excused => FontAwesomeIcons.ban,
  CellStatus.inProgress => FontAwesomeIcons.pen,
  CellStatus.notGraded || CellStatus.graded => null,
};

/// What a grade reads as: "87%" or its letter, and "—" for no grade.
String gradeText(double? percent, String? letter, {required bool letters}) {
  if (percent == null) return '—';
  if (letters && letter != null) return letter;
  return formatPercent(percent, decimals: 0);
}

/// The spoken form: always both percent and letter when there is one.
String gradeSemantics(BuildContext context, double? percent, String? letter) {
  if (percent == null) return '—';
  final p = formatPercent(percent);
  return letter == null ? p : context.l10n.gradebookGradeWithLetter(p, letter);
}

/// A grade chip tinted by tier with the grade printed on it; a status glyph
/// sits beside it for missing, excused and in-progress work.
class GradeBadge extends StatelessWidget {
  const new({
    required this.percent,
    required this.letter,
    required this.letters,
    this.status = CellStatus.graded,
    this.width = 64,
    super.key,
  });

  final double? percent;
  final String? letter;
  final bool letters;
  final CellStatus status;
  final double width;

  @override
  Widget build(BuildContext context) {
    final glyph = statusGlyph(status);
    final excused = status == CellStatus.excused;
    final text = excused
        ? context.l10n.gradebookExcusedShort
        : gradeText(percent, letter, letters: letters);
    final tone = percent == null
        ? (background: primaryDark, foreground: primaryLighter)
        : tierTone(gradeTier(percent!));
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            FaIcon(glyph, size: 12, color: accent),
            const SizedBox(width: 4),
          ],
          Container(
            constraints: BoxConstraints(minWidth: math.min(width, 48)),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: tone.background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: RubricTextStyles.caption.copyWith(
                color: tone.foreground,
                fontFamily: Fonts.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String dueLabel(BuildContext context, Assignment a) {
  final due = a.dueDate;
  if (due == null) return context.l10n.gradebookNoDueDate;
  final locale = Localizations.localeOf(context).toLanguageTag();
  return context.l10n.gradebookDue(DateFormat.MMMd(locale).format(due));
}

String shortDate(BuildContext context, DateTime date) =>
    DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag())
        .format(date);

/// A titled panel for charts and tables on analytics surfaces.
class AnalyticsPanel extends StatelessWidget {
  const new({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Insets.md),
      padding: const EdgeInsets.fromLTRB(Insets.md, Insets.md, Insets.md, 20),
      decoration: BoxDecoration(color: primaryDark, borderRadius: Corners.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Semantics(header: true, child: CardHint(title))),
              ?trailing,
            ],
          ),
          const SizedBox(height: Insets.md),
          child,
        ],
      ),
    );
  }
}

/// Side padding that keeps content ~720pt wide on tablets.
EdgeInsets contentPadding(BuildContext context, {double maxWidth = 720}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = math.max(Insets.lg, (width - maxWidth) / 2);
  return EdgeInsets.symmetric(horizontal: side);
}
