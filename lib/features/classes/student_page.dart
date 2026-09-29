import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/export/export_actions.dart';
import 'package:rubric/features/gradebook/gradebook_model.dart';
import 'package:rubric/features/gradebook/gradebook_providers.dart';
import 'package:rubric/features/gradebook/widgets/charts.dart';
import 'package:rubric/features/gradebook/widgets/grade_visuals.dart';
import 'package:rubric/l10n/l10n.dart';

/// How many strengths and weaknesses to list.
const _objectiveCount = 3;

/// One student's profile: details, overall grade, trend, objective strengths
/// and weaknesses against the class, and every assignment's grade.
class StudentPage extends ConsumerWidget {
  const new({required this.courseId, required this.studentId, super.key});

  final String courseId;
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final student = ref.watch(studentProvider(studentId));
    final gradebook = ref.watch(
      studentGradebookProvider((courseId, studentId)),
    );
    final s = student.value;

    if (student.hasValue && s == null) {
      return RubricPage(
        title: l10n.studentNotFound,
        children: [EmptyState(title: l10n.studentNotFound)],
      );
    }
    if (s == null || gradebook.value == null) {
      return RubricPage(
        title: s?.displayName ?? '',
        slivers: [
          SliverAsyncView(
            value: student.hasError ? student : gradebook,
            data: (_) => const SliverToBoxAdapter(),
          ),
        ],
      );
    }

    final gb = gradebook.requireValue;
    final row = gb.rowFor(studentId)!;
    final subtitle = [
      if (s.studentNumber.trim().isNotEmpty)
        l10n.studentNumber(s.studentNumber),
      if (s.email.trim().isNotEmpty) s.email,
    ].join(' · ');

    return RubricPage(
      title: s.displayName,
      subtitle: subtitle.isEmpty ? null : subtitle,
      actions: [
        HeaderAction(
          icon: FontAwesomeIcons.filePdf,
          label: l10n.studentExportReport,
          onTap: () => _pickReport(context, s, row),
        ),
        HeaderAction(
          icon: FontAwesomeIcons.pen,
          label: l10n.studentEdit,
          onTap: () => _edit(context, ref, s),
        ),
      ],
      slivers: [
        SliverPadding(
          padding: contentPadding(context),
          sliver: SliverList.list(
            children: [
              _Summary(gradebook: gb, row: row),
              const SizedBox(height: Insets.md),
              RubricCard(
                cardHintText: l10n.studentNotes,
                cardTitleText: s.notes.trim().isEmpty
                    ? l10n.studentNotesEmpty
                    : s.notes.trim(),
                color: s.notes.trim().isEmpty ? primaryDark : primaryCard,
                onTap: () => _edit(context, ref, s),
              ),
              ..._trend(context, gb),
              ..._objectives(context, gb),
              SectionLabel(l10n.studentHistoryTitle),
              if (row.cells.isEmpty)
                Text(
                  l10n.studentHistoryEmpty,
                  style: RubricTextStyles.bodySmall,
                )
              else
                for (final cell in row.cells.reversed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Insets.sm),
                    child: _HistoryCard(
                      cell: cell,
                      onTap: () => context.push(
                        Routes.grade(courseId, cell.assignment.id, studentId),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _trend(BuildContext context, Gradebook gb) {
    final l10n = context.l10n;
    final mine = gb.studentTrend(studentId);
    if (mine.isEmpty) return const [];
    final index = {for (final (i, a) in gb.assignments.indexed) a.id: i};
    final series = [
      TrendSeries(
        label: l10n.studentTrendYou,
        color: accent,
        points: [for (final p in mine) (index[p.assignment.id]!, p.percent)],
      ),
      TrendSeries(
        label: l10n.studentTrendClass,
        color: primaryLight,
        dashed: true,
        points: [
          for (final p in gb.classTrend) (index[p.assignment.id]!, p.percent),
        ],
      ),
    ];
    return [
      const SizedBox(height: Insets.lg),
      AnalyticsPanel(
        title: l10n.studentTrendTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GradeTrendChart(
              title: l10n.studentTrendTitle,
              series: series,
              xLabels: [
                for (final a in gb.assignments)
                  shortDate(context, assignmentDate(a)),
              ],
            ),
            const SizedBox(height: Insets.sm),
            SeriesKey(series: series),
          ],
        ),
      ),
    ];
  }

  List<Widget> _objectives(BuildContext context, Gradebook gb) {
    final l10n = context.l10n;
    final all = studentObjectives(gb, studentId);
    if (all.isEmpty) {
      return [
        SectionLabel(l10n.studentStrengthsTitle),
        Text(l10n.studentObjectivesEmpty, style: RubricTextStyles.bodySmall),
      ];
    }
    final strengths = all.where((c) => c.delta > 0).take(_objectiveCount);
    final weaknesses = all.reversed
        .where((c) => c.delta < 0)
        .take(_objectiveCount);
    // With nothing above or below the class, show the best ones anyway so
    // the section is never blank.
    final shownStrengths = strengths.isEmpty && weaknesses.isEmpty
        ? all.take(_objectiveCount)
        : strengths;
    return [
      if (shownStrengths.isNotEmpty) ...[
        SectionLabel(l10n.studentStrengthsTitle),
        for (final c in shownStrengths) _ObjectiveCard(comparison: c),
      ],
      if (weaknesses.isNotEmpty) ...[
        SectionLabel(l10n.studentWeaknessesTitle),
        for (final c in weaknesses) _ObjectiveCard(comparison: c),
      ],
    ];
  }

  Future<void> _pickReport(
    BuildContext context,
    Student student,
    GradebookRow row,
  ) async {
    final l10n = context.l10n;
    final graded = row.cells.where((c) => c.evaluation != null).toList();
    if (graded.isEmpty) {
      showRubricSnack(context, l10n.studentExportNothing);
      return;
    }
    final picked = await showRubricSheet<GradeCell>(
      context: context,
      child: RubricSheet(
        title: l10n.studentExportReport,
        child: Column(
          children: [
            for (final cell in graded.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.sm),
                child: Builder(
                  builder: (sheet) => _HistoryCard(
                    cell: cell,
                    onTap: () => Navigator.of(sheet).pop(cell),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await exportStudentReportPdf(
      context,
      assignment: picked.assignment,
      student: student,
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Student s) async {
    final l10n = context.l10n;
    final updated = await showRubricSheet<Student>(
      context: context,
      child: _EditStudentSheet(student: s),
    );
    if (updated == null || updated == s) return;
    final repo = ref.read(courseRepositoryProvider);
    await repo.saveStudent(updated);
    if (!context.mounted) return;
    showRubricSnack(
      context,
      l10n.studentSaved,
      action: SnackBarAction(
        label: l10n.studentUndo,
        textColor: accent,
        onPressed: () => repo.saveStudent(s),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const new({required this.gradebook, required this.row});

  final Gradebook gradebook;
  final GradebookRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final average = row.average;
    final letter = gradebook.letterFor(average);
    final tone = average == null ? null : tierTone(gradeTier(average));
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _Tile(
            value: formatPercent(average),
            label: l10n.studentAverage,
          ),
        ),
        const SizedBox(width: Insets.sm),
        Expanded(
          flex: 2,
          child: _Tile(
            value: letter ?? '—',
            label: l10n.studentLetter,
            color: tone?.background ?? primaryCard,
            valueColor: tone?.foreground ?? white,
          ),
        ),
        const SizedBox(width: Insets.sm),
        Expanded(
          flex: 2,
          child: _Tile(
            value: '${row.missingCount}',
            label: l10n.studentMissing,
          ),
        ),
        const SizedBox(width: Insets.sm),
        Expanded(
          flex: 3,
          child: _Tile(
            value: l10n.studentGradedOf(row.gradedCount, row.cells.length),
            label: l10n.studentGraded,
          ),
        ),
      ],
    );
  }
}

class _ObjectiveCard extends StatelessWidget {
  const new({required this.comparison});

  final ObjectiveComparison comparison;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = comparison;
    final points = c.delta.abs().toStringAsFixed(0);
    final relation = points == '0'
        ? l10n.studentLevel
        : c.delta > 0
        ? l10n.studentAbove(points)
        : l10n.studentBelow(points);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: RubricCard(
        cardHintText: l10n.studentObjectiveCompare(
          formatPercent(c.student, decimals: 0),
          formatPercent(c.classMean, decimals: 0),
        ),
        cardTitleText: c.title,
        trailing: Text(
          relation,
          textAlign: TextAlign.end,
          style: RubricTextStyles.caption.copyWith(
            color: c.delta >= 0 ? accent : primaryLighter,
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const new({required this.cell, required this.onTap});

  final GradeCell cell;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: gradeSemantics(context, cell.percent, cell.letter),
      child: RubricCard(
        cardHintText:
            '${dueLabel(context, cell.assignment)} · '
            '${statusLabel(context, cell.status)}',
        cardTitleText: cell.assignment.title,
        titleMaxLines: 2,
        onTap: onTap,
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GradeBadge(
              percent: cell.percent,
              letter: cell.letter,
              letters: false,
              status: cell.status,
            ),
            if (cell.letter != null) ...[
              const SizedBox(height: 4),
              Text(cell.letter!, style: RubricTextStyles.listTitle),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditStudentSheet extends StatefulWidget {
  const new({required this.student});

  final Student student;

  @override
  State<_EditStudentSheet> createState() => _EditStudentSheetState();
}

class _EditStudentSheetState extends State<_EditStudentSheet> {
  late final _first = TextEditingController(text: widget.student.firstName);
  late final _last = TextEditingController(text: widget.student.lastName);
  late final _number = TextEditingController(
    text: widget.student.studentNumber,
  );
  late final _email = TextEditingController(text: widget.student.email);
  late final _notes = TextEditingController(text: widget.student.notes);
  var _showError = false;

  @override
  void dispose() {
    for (final c in [_first, _last, _number, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_first.text.trim().isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(
      widget.student.copyWith(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        studentNumber: _number.text.trim(),
        email: _email.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget field(
      TextEditingController controller,
      String hint, {
      TextInputType? keyboard,
      TextCapitalization caps = TextCapitalization.words,
      int? maxLines = 1,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: RubricFormWell(
        child: RubricTextField(
          controller: controller,
          hintText: hint,
          keyboardType: keyboard,
          textCapitalization: caps,
          maxLines: maxLines,
          textInputAction: maxLines == 1
              ? TextInputAction.next
              : TextInputAction.newline,
          style: RubricTextStyles.bodySmall.copyWith(fontSize: 20),
        ),
      ),
    );

    return RubricSheet(
      title: l10n.studentEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field(_first, l10n.studentFirstName),
          if (_showError)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: Text(
                l10n.studentFirstNameRequired,
                style: RubricTextStyles.caption.copyWith(color: accent),
              ),
            ),
          field(_last, l10n.studentLastName),
          field(_number, l10n.studentNumberHint, caps: TextCapitalization.none),
          field(
            _email,
            l10n.studentEmailHint,
            keyboard: TextInputType.emailAddress,
            caps: TextCapitalization.none,
          ),
          field(
            _notes,
            l10n.studentNotesHint,
            caps: TextCapitalization.sentences,
            maxLines: null,
          ),
          const SizedBox(height: Insets.md),
          AccentButton(label: l10n.studentSave, onTap: _save, widthFactor: .2),
        ],
      ),
    );
  }
}

/// A [StatTile] read as its own stop by screen readers rather than merged
/// with its neighbours.
class _Tile extends StatelessWidget {
  const new({
    required this.value,
    required this.label,
    this.color = primaryCard,
    this.valueColor = white,
  });

  final String value;
  final String label;
  final Color color;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: StatTile(
      value: value,
      label: label,
      color: color,
      valueColor: valueColor,
    ),
  );
}
