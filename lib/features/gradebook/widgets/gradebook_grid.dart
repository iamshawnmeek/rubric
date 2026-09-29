import 'package:flutter/material.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/features/gradebook/gradebook_model.dart';
import 'package:rubric/features/gradebook/widgets/grade_visuals.dart';
import 'package:rubric/l10n/l10n.dart';

const _nameWidth = 148.0;
const _averageWidth = 84.0;
const _cellWidth = 96.0;
const _rowHeight = 56.0;
const _headerHeight = 76.0;
const _footerHeight = 56.0;

/// Students × assignments. The name and average columns stay put while the
/// assignments scroll sideways; the header and class-mean footer stay put
/// while the students scroll.
class GradebookGrid extends StatefulWidget {
  const new({
    required this.gradebook,
    required this.rows,
    required this.letters,
    required this.onCellTap,
    required this.onStudentTap,
    required this.onAssignmentTap,
    super.key,
  });

  final Gradebook gradebook;

  /// The rows to show, already sorted and filtered.
  final List<GradebookRow> rows;
  final bool letters;
  final void Function(GradeCell cell) onCellTap;
  final void Function(Student student) onStudentTap;
  final void Function(Assignment assignment) onAssignmentTap;

  @override
  State<GradebookGrid> createState() => _GradebookGridState();
}

class _GradebookGridState extends State<GradebookGrid> {
  final _frozen = ScrollController();
  final _body = ScrollController();
  final _horizontal = ScrollController();
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    _frozen.addListener(() => _sync(_frozen, _body));
    _body.addListener(() => _sync(_body, _frozen));
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients || !from.hasClients) return;
    if (to.offset == from.offset) return;
    _syncing = true;
    to.jumpTo(from.offset);
    _syncing = false;
  }

  @override
  void dispose() {
    _frozen.dispose();
    _body.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gb = widget.gradebook;
    final assignments = gb.assignments;
    final rows = widget.rows;
    final classAverage = gb.classAverage;

    final frozen = SizedBox(
      width: _nameWidth + _averageWidth,
      child: Column(
        children: [
          SizedBox(
            height: _headerHeight,
            child: Row(
              children: [
                _HeaderLabel(l10n.gradebookStudentColumn, width: _nameWidth),
                _HeaderLabel(
                  l10n.gradebookAverageColumn,
                  width: _averageWidth,
                  center: true,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _frozen,
              itemExtent: _rowHeight,
              itemCount: rows.length,
              itemBuilder: (context, i) => _FrozenRow(
                row: rows[i],
                odd: i.isOdd,
                letter: gb.letterFor(rows[i].average),
                letters: widget.letters,
                onTap: () => widget.onStudentTap(rows[i].student),
              ),
            ),
          ),
          _FooterRow(
            children: [
              SizedBox(
                width: _nameWidth,
                child: Padding(
                  padding: const EdgeInsets.only(left: Insets.sm),
                  child: Text(
                    l10n.gradebookClassMean,
                    style: RubricTextStyles.caption,
                  ),
                ),
              ),
              SizedBox(
                width: _averageWidth,
                child: Center(
                  child: Semantics(
                    label:
                        '${l10n.gradebookClassMean}, ${l10n.gradebookAverageColumn}: '
                        '${gradeSemantics(context, classAverage, gb.letterFor(classAverage))}',
                    child: GradeBadge(
                      percent: classAverage,
                      letter: gb.letterFor(classAverage),
                      letters: widget.letters,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final scrolling = Scrollbar(
      controller: _horizontal,
      child: SingleChildScrollView(
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _cellWidth * assignments.length,
          child: Column(
            children: [
              SizedBox(
                height: _headerHeight,
                child: Row(
                  children: [
                    for (final a in assignments)
                      _AssignmentHeader(
                        assignment: a,
                        mean: gb.summaryFor(a.id).mean,
                        onTap: () => widget.onAssignmentTap(a),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _body,
                  itemExtent: _rowHeight,
                  itemCount: rows.length,
                  itemBuilder: (context, i) => ColoredBox(
                    color: i.isOdd ? _stripe : secondary,
                    child: Row(
                      children: [
                        for (final cell in rows[i].cells)
                          _Cell(
                            cell: cell,
                            student: rows[i].student,
                            letters: widget.letters,
                            onTap: () => widget.onCellTap(cell),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              _FooterRow(
                children: [
                  for (final a in assignments)
                    SizedBox(
                      width: _cellWidth,
                      child: Center(child: _meanBadge(context, a)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Corners.card,
        border: Border.all(color: primaryDark),
      ),
      child: ClipRRect(
        borderRadius: Corners.card,
        child: Row(
          children: [
            frozen,
            Container(width: 1, color: primaryDark),
            Expanded(child: scrolling),
          ],
        ),
      ),
    );
  }

  Widget _meanBadge(BuildContext context, Assignment a) {
    final mean = widget.gradebook.summaryFor(a.id).mean;
    final letter = mean == null ? null : a.rubric.scale.letterFor(mean);
    return Semantics(
      label:
          '${context.l10n.gradebookClassMean}, ${a.title}: '
          '${gradeSemantics(context, mean, letter)}',
      child: GradeBadge(percent: mean, letter: letter, letters: widget.letters),
    );
  }
}

final Color _stripe = primaryDark.withValues(alpha: .35);

class _HeaderLabel extends StatelessWidget {
  const new(this.text, {required this.width, this.center = false});

  final String text;
  final double width;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: _headerHeight,
      color: primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      child: Text(
        text.toUpperCase(),
        style: RubricTextStyles.sectionLabel.copyWith(fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _AssignmentHeader extends StatelessWidget {
  const new({
    required this.assignment,
    required this.mean,
    required this.onTap,
  });

  final Assignment assignment;
  final double? mean;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final letter = mean == null
        ? null
        : assignment.rubric.scale.letterFor(mean!);
    return Semantics(
      button: true,
      label: context.l10n.gradebookAssignmentSemantics(
        '${assignment.title}, ${dueLabel(context, assignment)}',
        gradeSemantics(context, mean, letter),
      ),
      excludeSemantics: true,
      child: Material(
        color: primaryDark,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: _cellWidth,
            height: _headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: secondary)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  assignment.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: RubricTextStyles.caption.copyWith(
                    color: white,
                    fontFamily: Fonts.black,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  dueLabel(context, assignment),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RubricTextStyles.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FrozenRow extends StatelessWidget {
  const new({
    required this.row,
    required this.odd,
    required this.letter,
    required this.letters,
    required this.onTap,
  });

  final GradebookRow row;
  final bool odd;
  final String? letter;
  final bool letters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final average = row.average;
    return Semantics(
      button: true,
      label: context.l10n.gradebookStudentSemantics(
        row.student.displayName,
        gradeSemantics(context, average, letter),
      ),
      excludeSemantics: true,
      child: Material(
        color: odd ? _stripe : secondary,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              SizedBox(
                width: _nameWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                  child: Text(
                    row.student.sortName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: RubricTextStyles.bodySmall.copyWith(
                      color: white,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _averageWidth,
                child: Center(
                  child: GradeBadge(
                    percent: average,
                    letter: letter,
                    letters: letters,
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

class _Cell extends StatelessWidget {
  const new({
    required this.cell,
    required this.student,
    required this.letters,
    required this.onTap,
  });

  final GradeCell cell;
  final Student student;
  final bool letters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.gradebookCellSemantics(
        student.displayName,
        cell.assignment.title,
        gradeSemantics(context, cell.percent, cell.letter),
        statusLabel(context, cell.status),
      ),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: _cellWidth,
          height: _rowHeight,
          child: Center(
            child: GradeBadge(
              percent: cell.percent,
              letter: cell.letter,
              letters: letters,
              status: cell.status,
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterRow extends StatelessWidget {
  const new({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _footerHeight,
      color: primaryDark,
      child: Row(children: children),
    );
  }
}
