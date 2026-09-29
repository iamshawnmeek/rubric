import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/grading/grading_controller.dart';
import 'package:rubric/l10n/l10n.dart';

/// The student's initials in a round badge.
class InitialsAvatar extends StatelessWidget {
  const new({
    required this.student,
    this.size = 56,
    this.highlighted = false,
    super.key,
  });

  final Student student;
  final double size;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: highlighted ? accent : primaryDark,
        ),
        child: Text(
          student.initials.isEmpty ? '?' : student.initials,
          style: RubricTextStyles.listTitle.copyWith(
            fontSize: size * .36,
            color: highlighted ? secondary : white,
          ),
        ),
      ),
    );
  }
}

/// Avatar, live grade (percent + letter) and objective progress — updates on
/// every edit because it reads the same session the controls write.
class GradeSummary extends ConsumerWidget {
  const new({required this.session, super.key});

  final GradingSession session;

  /// Fixed height so it can pin above the rubric while the teacher scrolls.
  static const double height = 116;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final student = session.current!;
    final result = session.result;
    final excused = session.evaluation.status == EvaluationStatus.excused;
    final percentText = excused
        ? l10n.gradingExcusedGrade
        : result.percent == null
        ? l10n.gradingNoGrade
        : formatPercent(result.percent, decimals: settings.decimals);
    final letter = settings.showLetterGrades && !excused ? result.letter : null;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: primaryCard,
          borderRadius: Corners.card,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Row(
                children: [
                  InitialsAvatar(student: student, size: 44),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      label: l10n.gradingGradeSemantics(
                        percentText,
                        letter ?? '',
                      ),
                      excludeSemantics: true,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CardHint(l10n.gradingGradeLabel, fontSize: 14),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                percentText,
                                key: const Key('grading-live-grade'),
                                style: RubricTextStyles.statValue.copyWith(
                                  fontSize: 28,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (letter != null)
                    Container(
                      key: const Key('grading-live-letter'),
                      constraints: const BoxConstraints(minWidth: 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: Corners.card,
                      ),
                      alignment: Alignment.center,
                      child: ExcludeSemantics(
                        child: Text(
                          letter,
                          style: RubricTextStyles.statValue.copyWith(
                            fontSize: 28,
                            color: secondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                Expanded(child: RubricProgressBar(value: result.progress)),
                const SizedBox(width: Insets.sm),
                Text(
                  l10n.gradingProgress(result.scoredCount, result.totalCount),
                  style: RubricTextStyles.caption,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// [GradeSummary] pinned to the top of the grading scroll view, on the page
/// background so the rubric scrolls cleanly beneath it.
class PinnedGradeSummary extends StatelessWidget {
  const new({required this.session, required this.maxWidth, super.key});

  final GradingSession session;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SliverPersistentHeader(
    pinned: true,
    delegate: _SummaryDelegate(session, maxWidth),
  );
}

class _SummaryDelegate extends SliverPersistentHeaderDelegate {
  new(this.session, this.maxWidth);

  final GradingSession session;
  final double maxWidth;

  static const double _extent = GradeSummary.height + Insets.sm * 2;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(
        color: secondary,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth + Insets.lg * 2),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg,
                vertical: Insets.sm,
              ),
              child: GradeSummary(session: session),
            ),
          ),
        ),
      );

  @override
  bool shouldRebuild(_SummaryDelegate old) =>
      old.session != session || old.maxWidth != maxWidth;
}
