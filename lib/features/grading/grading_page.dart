import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/grading/grading_controller.dart';
import 'package:rubric/features/grading/widgets/grade_summary.dart';
import 'package:rubric/features/grading/widgets/objective_card.dart';
import 'package:rubric/features/grading/widgets/overall_comment.dart';
import 'package:rubric/features/grading/widgets/status_controls.dart';
import 'package:rubric/features/grading/widgets/student_list_pane.dart';
import 'package:rubric/l10n/l10n.dart';

/// Grades one assignment student by student. Opened on [studentId]; prev/next,
/// swipe, the tablet roster and "next ungraded" move within the session
/// without leaving the page.
class GradingPage extends ConsumerWidget {
  const new({required this.assignmentId, required this.studentId, super.key});

  final String assignmentId;
  final String studentId;

  /// Wider than this, the roster sits beside the rubric.
  static const twoPaneBreakpoint = 900.0;

  /// Content never stretches past this on wide screens.
  static const maxContentWidth = 720.0;

  GradingArgs get _args => (assignmentId: assignmentId, studentId: studentId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(gradingControllerProvider(_args));

    return switch (session) {
      AsyncData(:final value) => _loaded(context, value),
      AsyncError(:final error) => RubricPage(
        title: l10n.gradingTitle,
        showBack: true,
        onBack: () => _leave(context, null),
        children: [
          EmptyState(
            title: error is GradingAssignmentMissing
                ? l10n.gradingNotFoundTitle
                : error.toString(),
          ),
        ],
      ),
      _ => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: accent)),
      ),
    };
  }

  Widget _loaded(BuildContext context, GradingSession session) {
    final l10n = context.l10n;
    if (session.current == null) {
      return RubricPage(
        title: session.assignment.title,
        showBack: true,
        onBack: () => _leave(context, session),
        children: [
          EmptyState(
            title: l10n.gradingNoStudentsTitle,
            message: l10n.gradingNoStudentsMessage,
          ),
        ],
      );
    }
    if (session.finished) {
      return _FinishedView(
        args: _args,
        session: session,
        onBack: () => _leave(context, session),
      );
    }

    final body = _GradingBody(
      args: _args,
      session: session,
      onBack: () => _leave(context, session),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < twoPaneBreakpoint) return body;
        return Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 320,
                child: StudentListPane(args: _args, session: session),
              ),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }

  void _leave(BuildContext context, GradingSession? session) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else if (session != null) {
      router.go(
        Routes.assignment(session.assignment.courseId, session.assignment.id),
      );
    } else {
      router.go(Routes.home);
    }
  }
}

class _GradingBody extends ConsumerWidget {
  const new({required this.args, required this.session, required this.onBack});

  final GradingArgs args;
  final GradingSession session;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(gradingControllerProvider(args).notifier);
    final student = session.current!;
    final index = session.index;
    final rubric = session.rubric;
    final evaluation = session.evaluation;

    var number = 0;
    final groups = <Widget>[
      for (final group in rubric.groups) ...[
        SectionLabel(l10n.gradingGroupHeader(group.title, group.weight)),
        for (final objective in group.objectives) ...[
          ObjectiveCard(
            key: ValueKey('objective-${student.id}-${objective.id}'),
            args: args,
            rubric: rubric,
            objective: objective,
            number: ++number,
            evaluation: evaluation,
          ),
          const SizedBox(height: Insets.md),
        ],
      ],
    ];

    void undo() {
      controller.undo();
      showRubricSnack(context, l10n.gradingUndone);
    }

    return GestureDetector(
      // Swipe between students; sliders and fields win their own drags.
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 300) return;
        controller.step(forward: v < 0);
      },
      child: RubricPage(
        key: ValueKey('grading-${student.id}'),
        title: student.displayName,
        subtitle:
            '${l10n.gradingPosition(index + 1, session.students.length)} · '
            '${session.assignment.title}',
        showBack: true,
        onBack: onBack,
        actions: [
          if (session.canUndo)
            HeaderAction(
              icon: FontAwesomeIcons.rotateLeft,
              label: l10n.gradingUndo,
              onTap: undo,
            ),
          _NavAction(
            icon: FontAwesomeIcons.chevronLeft,
            label: l10n.gradingPreviousStudent,
            enabled: index > 0,
            onTap: () => controller.step(forward: false),
          ),
          _NavAction(
            icon: FontAwesomeIcons.chevronRight,
            label: l10n.gradingNextStudent,
            enabled: index < session.students.length - 1,
            onTap: () => controller.step(forward: true),
          ),
        ],
        slivers: [
          PinnedGradeSummary(
            session: session,
            maxWidth: GradingPage.maxContentWidth,
          ),
          _Constrained(
            children: [
              SectionLabel(l10n.gradingStatusSection),
              StatusControls(args: args, session: session),
              if (rubric.objectives.isEmpty)
                EmptyState(title: l10n.gradingNoObjectives),
              ...groups,
              SectionLabel(l10n.gradingCommentSection),
              OverallComment(args: args, comment: evaluation.comment),
            ],
          ),
        ],
        bottomCta: AccentButton(
          label: session.allGraded
              ? l10n.gradingFinish
              : l10n.gradingNextUngraded,
          widthFactor: .2,
          onTap: controller.nextUngraded,
        ),
      ),
    );
  }
}

/// A header action that dims and stops taking taps at the end of the roster.
class _NavAction extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    enabled: enabled,
    child: IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : .35,
        child: HeaderAction(icon: icon, label: label, onTap: onTap),
      ),
    ),
  );
}

/// Pads its children to the page gutter, centred at [GradingPage.maxContentWidth]
/// on wide screens so the rubric never looks stretched.
class _Constrained extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(
          Insets.lg,
          (constraints.crossAxisExtent - GradingPage.maxContentWidth) / 2,
        );
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverList.list(children: children),
        );
      },
    );
  }
}

class _FinishedView extends ConsumerWidget {
  const new({required this.args, required this.session, required this.onBack});

  final GradingArgs args;
  final GradingSession session;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final decimals = ref.watch(settingsProvider.select((s) => s.decimals));
    final average = session.classAverage;
    final letter = average == null
        ? null
        : session.rubric.scale.letterFor(average);
    return RubricPage(
      title: l10n.gradingFinishedTitle,
      subtitle: session.assignment.title,
      showBack: true,
      onBack: onBack,
      bottomCta: AccentButton(
        label: l10n.gradingBackToAssignment,
        widthFactor: .15,
        onTap: () => context.go(
          Routes.assignment(session.assignment.courseId, session.assignment.id),
        ),
      ),
      children: [
        Text(
          l10n.gradingFinishedMessage(session.gradedCount),
          style: RubricTextStyles.pageInfo,
        ),
        const SizedBox(height: Insets.lg),
        Row(
          children: [
            Expanded(
              child: StatTile(
                key: const Key('grading-class-average'),
                value: formatPercent(average, decimals: decimals),
                label: l10n.gradingClassAverage,
              ),
            ),
            if (letter != null) ...[
              const SizedBox(width: Insets.sm),
              StatTile(
                value: letter,
                label: l10n.gradingGradeLabel,
                color: accent,
                valueColor: secondary,
              ),
            ],
          ],
        ),
        const SizedBox(height: Insets.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: ref
                .read(gradingControllerProvider(args).notifier)
                .dismissFinished,
            child: Text(l10n.gradingKeepReviewing),
          ),
        ),
      ],
    );
  }
}
