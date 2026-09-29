import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/assignments/assignment_logic.dart';
import 'package:rubric/features/assignments/assignment_sheets.dart';
import 'package:rubric/features/assignments/assignment_widgets.dart';
import 'package:rubric/features/export/export_actions.dart';
import 'package:rubric/l10n/l10n.dart';

/// The assignment hub: progress, class results and every student's status
/// and grade, with the way into grading.
class AssignmentPage extends ConsumerStatefulWidget {
  const new({required this.courseId, required this.assignmentId, super.key});

  final String courseId;
  final String assignmentId;

  @override
  ConsumerState<AssignmentPage> createState() => _AssignmentPageState();
}

class _AssignmentPageState extends ConsumerState<AssignmentPage> {
  HubSort _sort = HubSort.name;
  HubFilter _filter = HubFilter.all;
  String _query = '';

  /// Students whose lazily-created evaluation is already being written, so a
  /// rebuild before the stream catches up does not write it twice.
  final _seeding = <String>{};

  /// Students added to the course after the assignment was created get their
  /// evaluation the first time the hub sees them.
  void _ensureEvaluations(
    Assignment assignment,
    List<Student> students,
    List<Evaluation> evaluations,
  ) {
    final missing = missingEvaluations(
      assignment,
      students.where((s) => !_seeding.contains(s.id)),
      evaluations,
    );
    if (missing.isEmpty) return;
    _seeding.addAll(missing.map((e) => e.studentId));
    unawaited(ref.read(assignmentRepositoryProvider).saveEvaluations(missing));
  }

  void _grade(Student student) => context.push(
    Routes.grade(widget.courseId, widget.assignmentId, student.id),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final assignmentAsync = ref.watch(assignmentProvider(widget.assignmentId));
    final studentsAsync = ref.watch(studentsProvider(widget.courseId));
    final evaluationsAsync = ref.watch(
      evaluationsProvider(widget.assignmentId),
    );

    final assignment = assignmentAsync.value;
    final students = studentsAsync.value;
    final evaluations = evaluationsAsync.value;

    if (assignmentAsync case AsyncData(value: null)) {
      return RubricPage(
        title: l10n.assignmentsNotFoundTitle,
        showBack: true,
        onBack: () => context.go(Routes.course(widget.courseId)),
        children: [EmptyState(title: l10n.assignmentsNotFound)],
      );
    }
    if (assignment == null || students == null || evaluations == null) {
      // Show whichever source is failing, else whichever is still loading.
      // Never hand SliverAsyncView one that already has data: its builder
      // would then have to produce the page, and a box there is not a sliver
      // (seen on device: "RenderViewport expected a child of type
      // RenderSliver" while the roster was still loading).
      final sources = [assignmentAsync, studentsAsync, evaluationsAsync];
      final pending = sources.firstWhere(
        (a) => a.hasError,
        orElse: () => sources.firstWhere(
          (a) => a.isLoading || !a.hasValue,
          orElse: () => assignmentAsync,
        ),
      );
      return RubricPage(
        title: '',
        showBack: true,
        slivers: [
          SliverAsyncView(
            value: pending,
            data: (_) => const SliverToBoxAdapter(),
          ),
        ],
      );
    }

    _ensureEvaluations(assignment, students, evaluations);
    final rows = hubRows(assignment, students, evaluations);
    final next = firstUngraded(rows);
    final started = rows.any((r) => r.status != EvaluationStatus.notStarted);
    final gutter = contentGutter(context);

    return RubricPage(
      title: assignment.title,
      subtitle: _subtitle(context, assignment),
      showBack: true,
      actions: [
        HeaderAction(
          key: const Key('assignments.menu'),
          icon: FontAwesomeIcons.ellipsis,
          label: l10n.assignmentsMenu,
          onTap: () => _openMenu(assignment, rows.length),
        ),
      ],
      bottomCta: assignment.closed || next == null
          ? null
          : AccentButton(
              key: const Key('assignments.gradeCta'),
              label: started
                  ? l10n.assignmentsContinueGrading
                  : l10n.assignmentsStartGrading,
              widthFactor: .2,
              onTap: () => _grade(next),
            ),
      slivers: [
        SliverPadding(
          padding: gutter,
          sliver: SliverList.list(
            children: [
              if (assignment.closed) ...[
                _ClosedBanner(onReopen: () => _setClosed(assignment, false)),
                const SizedBox(height: Insets.md),
              ],
              if (assignment.description.trim().isNotEmpty) ...[
                Text(assignment.description, style: RubricTextStyles.bodySmall),
                const SizedBox(height: Insets.md),
              ],
              _ProgressCard(graded: gradedCount(rows), total: rows.length),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: Insets.md),
                _StatsCard(assignment: assignment, rows: rows),
              ],
              SectionLabel(l10n.assignmentsStudentsSection),
              if (rows.isNotEmpty)
                _ListControls(
                  rows: rows,
                  sort: _sort,
                  filter: _filter,
                  onSort: (s) => setState(() => _sort = s),
                  onFilter: (f) => setState(() => _filter = f),
                  onQuery: (q) => setState(() => _query = q),
                ),
            ],
          ),
        ),
        _studentList(assignment, rows, students, gutter),
      ],
    );
  }

  Widget _studentList(
    Assignment assignment,
    List<HubRow> rows,
    List<Student> students,
    EdgeInsets gutter,
  ) {
    final l10n = context.l10n;
    if (students.isEmpty) {
      return SliverPadding(
        padding: gutter,
        sliver: SliverToBoxAdapter(
          child: EmptyState(
            title: l10n.assignmentsNoStudents,
            message: l10n.assignmentsNoStudentsMessage,
            action: FilledButton(
              onPressed: () =>
                  context.push(Routes.rosterImport(widget.courseId)),
              child: Text(l10n.assignmentsAddStudents),
            ),
          ),
        ),
      );
    }
    final shown = arrangeRows(
      rows,
      sort: _sort,
      filter: _filter,
      query: _query,
    );
    if (shown.isEmpty) {
      return SliverPadding(
        padding: gutter,
        sliver: SliverToBoxAdapter(
          child: EmptyState(title: l10n.assignmentsNoMatchingStudents),
        ),
      );
    }
    return SliverPadding(
      padding: gutter,
      sliver: SliverList.separated(
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(height: Insets.sm),
        itemBuilder: (context, i) => _StudentRow(
          key: ValueKey(shown[i].student.id),
          row: shown[i],
          onTap: () => _grade(shown[i].student),
          onActions: () => _studentActions(assignment, shown[i]),
        ),
      ),
    );
  }

  String _subtitle(BuildContext context, Assignment a) {
    final l10n = context.l10n;
    return [
      if (a.dueDate case final due?)
        l10n.assignmentsDueOn(formatDueDate(context, due)),
      a.rubric.title,
      l10n.assignmentsPoints(formatPoints(a.pointsPossible)),
    ].join(' · ');
  }

  // ---- Student quick actions ----

  Future<void> _saveWithUndo(
    Evaluation before,
    Evaluation after,
    String message,
  ) async {
    final repo = ref.read(assignmentRepositoryProvider);
    await repo.saveEvaluation(after);
    if (!mounted) return;
    showRubricSnack(
      context,
      message,
      action: SnackBarAction(
        label: context.l10n.assignmentsUndo,
        onPressed: () => repo.saveEvaluation(before.copyWith()),
      ),
    );
  }

  Future<void> _studentActions(Assignment assignment, HubRow row) async {
    final l10n = context.l10n;
    final action = await showStudentActions(context, row);
    if (action == null || !mounted) return;
    final e = row.evaluation;
    final name = row.student.displayName;
    switch (action) {
      case StudentAction.markMissing:
        await _saveWithUndo(
          e,
          e.copyWith(status: EvaluationStatus.missing),
          l10n.assignmentsMarkedMissing(name),
        );
      case StudentAction.excuse:
        await _saveWithUndo(
          e,
          e.copyWith(status: EvaluationStatus.excused),
          l10n.assignmentsMarkedExcused(name),
        );
      case StudentAction.clearMark:
        final cleared = e.copyWith(status: EvaluationStatus.notStarted);
        await _saveWithUndo(
          e,
          cleared.copyWith(
            status: Scoring.derivedStatus(assignment.rubric, cleared),
          ),
          l10n.assignmentsMarkCleared(name),
        );
      case StudentAction.reset:
        final ok = await confirm(
          context,
          title: l10n.assignmentsResetTitle(name),
          message: l10n.assignmentsResetMessage,
          confirmLabel: l10n.assignmentsResetConfirm,
        );
        if (!ok || !mounted) return;
        await _saveWithUndo(
          e,
          resetEvaluation(e),
          l10n.assignmentsResetDone(name),
        );
    }
  }

  // ---- Assignment menu ----

  Future<void> _openMenu(Assignment assignment, int studentCount) async {
    final action = await showAssignmentMenu(context, assignment);
    if (action == null || !mounted) return;
    switch (action) {
      case AssignmentAction.edit:
        await _editDetails(assignment);
      case AssignmentAction.updateRubric:
        await _updateRubric(assignment);
      case AssignmentAction.close:
        await _setClosed(assignment, true);
      case AssignmentAction.reopen:
        await _setClosed(assignment, false);
      case AssignmentAction.exportCsv:
        await exportAssignmentCsv(context, assignment: assignment);
      case AssignmentAction.exportPdf:
        await exportAssignmentReportsPdf(context, assignment: assignment);
      case AssignmentAction.delete:
        await _delete(assignment, studentCount);
    }
  }

  Future<void> _editDetails(Assignment assignment) async {
    final edited = await showEditDetails(context, assignment);
    if (edited == null) return;
    await ref.read(assignmentRepositoryProvider).save(edited);
  }

  Future<void> _setClosed(Assignment assignment, bool closed) async {
    await ref
        .read(assignmentRepositoryProvider)
        .save(assignment.copyWith(closed: closed));
    if (!mounted) return;
    showRubricSnack(
      context,
      closed
          ? context.l10n.assignmentsClosedDone
          : context.l10n.assignmentsReopenedDone,
    );
  }

  Future<void> _updateRubric(Assignment assignment) async {
    final l10n = context.l10n;
    final sourceId = assignment.sourceRubricId;
    final library = sourceId == null
        ? null
        : await ref.read(rubricRepositoryProvider).get(sourceId);
    if (!mounted) return;
    if (library == null) {
      showRubricSnack(context, l10n.assignmentsUpdateRubricGone);
      return;
    }
    if (!canAttach(library)) {
      showRubricSnack(
        context,
        l10n.assignmentsUpdateRubricNotReady(library.title),
        action: SnackBarAction(
          label: l10n.assignmentsFix,
          onPressed: () => context.push(Routes.buildRubric(library.id)),
        ),
      );
      return;
    }
    final ok = await confirm(
      context,
      title: l10n.assignmentsUpdateRubricTitle,
      message: l10n.assignmentsUpdateRubricMessage(library.title),
      confirmLabel: l10n.assignmentsUpdateRubricConfirm,
    );
    if (!ok) return;
    final repo = ref.read(assignmentRepositoryProvider);
    final (updated, evaluations) = resnapshot(
      assignment,
      library,
      await repo.evaluations(assignment.id),
    );
    await repo.save(updated);
    await repo.saveEvaluations(evaluations);
    if (!mounted) return;
    showRubricSnack(context, l10n.assignmentsUpdateRubricDone);
  }

  Future<void> _delete(Assignment assignment, int studentCount) async {
    final l10n = context.l10n;
    final ok = await confirm(
      context,
      title: l10n.assignmentsDeleteTitle(assignment.title),
      message: l10n.assignmentsDeleteMessage(studentCount),
      confirmLabel: l10n.assignmentsDeleteConfirm,
    );
    if (!ok || !mounted) return;
    final repo = ref.read(assignmentRepositoryProvider);
    context.go(Routes.course(widget.courseId));
    await repo.delete(assignment.id);
  }
}

class _ClosedBanner extends StatelessWidget {
  const new({required this.onReopen});

  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Insets.md,
        Insets.xs,
        Insets.xs,
        Insets.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: Corners.card,
        border: Border.all(color: accent),
      ),
      child: Row(
        children: [
          const FaIcon(FontAwesomeIcons.lock, size: 16, color: accent),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Text(
              l10n.assignmentsClosedBanner,
              style: RubricTextStyles.bodySmall,
            ),
          ),
          TextButton(
            onPressed: onReopen,
            child: Text(
              l10n.assignmentsReopen,
              style: RubricTextStyles.button.copyWith(color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const new({required this.graded, required this.total});

  final int graded;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = l10n.assignmentsGradedProgress(graded, total);
    return Semantics(
      label: '${l10n.assignmentsProgressHint}: $text',
      excludeSemantics: true,
      child: Container(
        padding: Insets.card,
        decoration: BoxDecoration(
          color: primaryCard,
          borderRadius: Corners.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardHint(l10n.assignmentsProgressHint),
            const SizedBox(height: Insets.xs),
            CardTitle(text, key: const Key('assignments.progress')),
            const SizedBox(height: Insets.sm),
            RubricProgressBar(value: total == 0 ? 0 : graded / total),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const new({required this.assignment, required this.rows});

  final Assignment assignment;
  final List<HubRow> rows;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rubric = assignment.rubric;
    final stats = AssignmentStats.compute(
      rubric,
      rows.map((r) => r.evaluation),
    );
    final overall = stats.overall;
    final weakestId = stats.weakestObjectiveId;
    final weakest = rubric.objectives
        .where((o) => o.id == weakestId)
        .firstOrNull;

    return Container(
      padding: Insets.card,
      decoration: BoxDecoration(color: primaryCard, borderRadius: Corners.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHint(l10n.assignmentsStatsTitle),
          const SizedBox(height: Insets.sm),
          if (overall.count == 0)
            Text(l10n.assignmentsStatsEmpty, style: RubricTextStyles.bodySmall)
          else ...[
            Row(
              children: [
                for (final (label, value) in [
                  (l10n.assignmentsStatMean, overall.mean),
                  (l10n.assignmentsStatMedian, overall.median),
                  (l10n.assignmentsStatHigh, overall.max),
                  (l10n.assignmentsStatLow, overall.min),
                ]) ...[
                  Expanded(
                    child: StatTile(
                      value: formatPercent(value, decimals: 0),
                      label: label,
                      color: primaryDark,
                    ),
                  ),
                  if (label != l10n.assignmentsStatLow)
                    const SizedBox(width: Insets.xs),
                ],
              ],
            ),
            const SizedBox(height: Insets.md),
            _LetterDistribution(counts: stats.letterCounts),
            if (weakest != null) ...[
              const SizedBox(height: Insets.md),
              Semantics(
                label:
                    '${l10n.assignmentsWeakestObjective}: ${weakest.title}, '
                    '${formatPercent(stats.objectiveMeans[weakest.id])}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.assignmentsWeakestObjective,
                      style: RubricTextStyles.caption,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${weakest.title} · '
                      '${formatPercent(stats.objectiveMeans[weakest.id])}',
                      key: const Key('assignments.weakest'),
                      style: RubricTextStyles.listTitle,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A stacked bar of how many students earned each letter, with a labelled
/// legend so the counts never rely on color alone.
class _LetterDistribution extends StatelessWidget {
  const new({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = counts.entries.toList();
    Color colorAt(int i) => seriesRamp[i % seriesRamp.length];
    final summary = entries.map((e) => '${e.key} ${e.value}').join(', ');

    return Semantics(
      label: '${l10n.assignmentsLetterDistribution}: $summary',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.assignmentsLetterDistribution,
            style: RubricTextStyles.caption,
          ),
          const SizedBox(height: Insets.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (i, e) in entries.indexed)
                    if (e.value > 0)
                      Expanded(
                        flex: e.value,
                        child: ColoredBox(color: colorAt(i)),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: Insets.md,
            runSpacing: Insets.xs,
            children: [
              for (final (i, e) in entries.indexed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorAt(i),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${e.key} ${e.value}',
                      style: RubricTextStyles.caption.copyWith(
                        color: e.value > 0 ? white : primaryLight,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ListControls extends StatelessWidget {
  const new({
    required this.rows,
    required this.sort,
    required this.filter,
    required this.onSort,
    required this.onFilter,
    required this.onQuery,
  });

  final List<HubRow> rows;
  final HubSort sort;
  final HubFilter filter;
  final ValueChanged<HubSort> onSort;
  final ValueChanged<HubFilter> onFilter;
  final ValueChanged<String> onQuery;

  /// Below this a search field is clutter.
  static const _searchThreshold = 8;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    int count(HubFilter f) => arrangeRows(rows, filter: f).length;
    String filterLabel(HubFilter f) => switch (f) {
      HubFilter.all => l10n.assignmentsFilterAll,
      HubFilter.ungraded => l10n.assignmentsFilterUngraded,
      HubFilter.complete => l10n.assignmentsStatusComplete,
      HubFilter.missing => l10n.assignmentsStatusMissing,
      HubFilter.excused => l10n.assignmentsStatusExcused,
    };
    String sortLabel(HubSort s) => switch (s) {
      HubSort.name => l10n.assignmentsSortName,
      HubSort.status => l10n.assignmentsSortStatus,
      HubSort.grade => l10n.assignmentsSortGrade,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.length >= _searchThreshold) ...[
          RubricFormWell(
            child: RubricTextField(
              key: const Key('assignments.studentSearch'),
              hintText: l10n.assignmentsSearchStudents,
              onChanged: onQuery,
              textCapitalization: TextCapitalization.words,
              style: RubricTextStyles.bodySmall,
              hintStyle: RubricTextStyles.bodySmall,
            ),
          ),
          const SizedBox(height: Insets.sm),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in HubFilter.values)
                if (f == HubFilter.all || count(f) > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: Insets.xs),
                    child: RubricChip(
                      key: Key('assignments.filter.${f.name}'),
                      label: '${filterLabel(f)} ${count(f)}',
                      selected: f == filter,
                      onTap: () => onFilter(f),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: Insets.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(l10n.assignmentsSortLabel, style: RubricTextStyles.caption),
              const SizedBox(width: Insets.xs),
              for (final s in HubSort.values)
                Padding(
                  padding: const EdgeInsets.only(right: Insets.xs),
                  child: RubricChip(
                    key: Key('assignments.sort.${s.name}'),
                    label: sortLabel(s),
                    selected: s == sort,
                    onTap: () => onSort(s),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Insets.md),
      ],
    );
  }
}

class _StudentRow extends StatelessWidget {
  const new({
    required this.row,
    required this.onTap,
    required this.onActions,
    super.key,
  });

  final HubRow row;
  final VoidCallback onTap;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = row.student.displayName;
    final result = row.result;
    final percent = row.status == EvaluationStatus.excused
        ? null
        : result.percent;
    final gradeText = percent == null
        ? '—'
        : l10n.assignmentsGradeValue(formatPercent(percent), result.letter!);
    final status = row.status.label(l10n);

    return Material(
      color: primaryCard,
      borderRadius: Corners.card,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '$name, $status, $gradeText',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: Corners.card,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.lg,
                    Insets.md,
                    Insets.xs,
                    Insets.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RubricTextStyles.listTitle,
                            ),
                            const SizedBox(height: 6),
                            StatusChip(row.status),
                          ],
                        ),
                      ),
                      const SizedBox(width: Insets.sm),
                      Text(
                        gradeText,
                        key: Key('assignments.grade.${row.student.id}'),
                        style: RubricTextStyles.listTitle.copyWith(
                          color: percent == null ? primaryLight : white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: Key('assignments.actions.${row.student.id}'),
            tooltip: l10n.assignmentsStudentActions(name),
            onPressed: onActions,
            icon: const FaIcon(
              FontAwesomeIcons.ellipsisVertical,
              color: primaryLighter,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}
