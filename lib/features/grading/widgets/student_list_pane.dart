import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/grading/grading_controller.dart';
import 'package:rubric/features/grading/widgets/grade_summary.dart';
import 'package:rubric/l10n/l10n.dart';

/// Tablet left pane: the roster in grading order with each student's grade.
class StudentListPane extends ConsumerWidget {
  const new({required this.args, required this.session, super.key});

  final GradingArgs args;
  final GradingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final decimals = ref.watch(settingsProvider.select((s) => s.decimals));
    return ColoredBox(
      color: primaryDark,
      child: SafeArea(
        right: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.pageTop,
                Insets.lg,
                Insets.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionLabel(
                  l10n.gradingStudentsPane,
                  trailing: Text(
                    '${session.gradedCount}/${session.students.length}',
                    style: RubricTextStyles.caption,
                  ),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: session.students.length,
              itemBuilder: (context, i) {
                final s = session.students[i];
                final selected = s.id == session.currentStudentId;
                final graded = session.isGraded(s.id);
                final e = session.evaluations[s.id];
                final percent = e == null
                    ? null
                    : Scoring.score(session.rubric, e).percent;
                final status = graded
                    ? l10n.gradingStudentGraded
                    : l10n.gradingStudentUngraded;
                return Semantics(
                  button: true,
                  selected: selected,
                  label: l10n.gradingStudentRowSemantics(s.displayName, status),
                  excludeSemantics: true,
                  child: Material(
                    color: selected ? primaryCard : Colors.transparent,
                    child: InkWell(
                      onTap: () => ref
                          .read(gradingControllerProvider(args).notifier)
                          .goTo(s.id),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 64),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Insets.lg,
                            vertical: Insets.xs,
                          ),
                          child: Row(
                            children: [
                              InitialsAvatar(
                                student: s,
                                size: 40,
                                highlighted: selected,
                              ),
                              const SizedBox(width: Insets.sm),
                              Expanded(
                                child: Text(
                                  s.sortName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: RubricTextStyles.bodySmall.copyWith(
                                    color: white,
                                  ),
                                ),
                              ),
                              if (percent != null)
                                Text(
                                  formatPercent(percent, decimals: decimals),
                                  style: RubricTextStyles.caption,
                                ),
                              const SizedBox(width: Insets.xs),
                              // Icon shape, not just colour, carries graded.
                              FaIcon(
                                graded
                                    ? FontAwesomeIcons.solidCircleCheck
                                    : FontAwesomeIcons.circle,
                                size: 16,
                                color: graded ? accent : inactive,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
