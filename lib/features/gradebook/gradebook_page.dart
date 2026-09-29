import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/features/export/export_actions.dart';
import 'package:rubric/features/gradebook/gradebook_model.dart';
import 'package:rubric/features/gradebook/gradebook_providers.dart';
import 'package:rubric/features/gradebook/widgets/analytics_view.dart';
import 'package:rubric/features/gradebook/widgets/grade_visuals.dart';
import 'package:rubric/features/gradebook/widgets/gradebook_grid.dart';
import 'package:rubric/l10n/l10n.dart';

enum _Tab { grid, analytics }

/// Show a search field once the roster is longer than this.
const _searchThreshold = 12;

class GradebookPage extends ConsumerStatefulWidget {
  const new({required this.courseId, super.key});

  final String courseId;

  @override
  ConsumerState<GradebookPage> createState() => _GradebookPageState();
}

class _GradebookPageState extends ConsumerState<GradebookPage> {
  _Tab _tab = _Tab.grid;
  GradebookSort _sort = GradebookSort.name;
  var _descending = false;
  var _letters = false;
  var _query = '';

  void _setSort(GradebookSort sort) => setState(() {
    if (_sort == sort) {
      _descending = !_descending;
    } else {
      _sort = sort;
      _descending = false;
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final course = ref.watch(courseProvider(widget.courseId));
    final gradebook = ref.watch(gradebookProvider(widget.courseId));
    final loadedCourse = course.value;

    if (course.hasValue && loadedCourse == null) {
      return RubricPage(
        title: l10n.gradebookTitle,
        children: [EmptyState(title: l10n.gradebookCourseMissing)],
      );
    }

    final padding = contentPadding(context);
    final gb = gradebook.value;
    final hasGrid = gb != null && !gb.isEmpty;

    return RubricPage(
      title: l10n.gradebookTitle,
      subtitle: loadedCourse?.name,
      actions: [
        if (loadedCourse != null && hasGrid)
          HeaderAction(
            icon: FontAwesomeIcons.fileCsv,
            label: l10n.gradebookExportCsv,
            onTap: () => exportGradebookCsv(context, course: loadedCourse),
          ),
      ],
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: SliverToBoxAdapter(
            child: SegmentedToggle<_Tab>(
              segments: {
                _Tab.grid: l10n.gradebookTabGrid,
                _Tab.analytics: l10n.gradebookTabAnalytics,
              },
              selected: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Insets.md)),
        if (gradebook is AsyncError || gb == null)
          SliverPadding(
            padding: padding,
            sliver: SliverAsyncView(
              value: gradebook,
              data: (_) => const SliverToBoxAdapter(),
            ),
          )
        else if (gb.rows.isEmpty)
          _emptySliver(
            padding,
            EmptyState(
              title: l10n.gradebookNoStudentsTitle,
              message: l10n.gradebookNoStudentsMessage,
            ),
          )
        else if (gb.assignments.isEmpty)
          _emptySliver(
            padding,
            EmptyState(
              title: l10n.gradebookNoAssignmentsTitle,
              message: l10n.gradebookNoAssignmentsMessage,
            ),
          )
        else if (_tab == _Tab.analytics)
          SliverPadding(
            padding: padding,
            sliver: SliverToBoxAdapter(
              child: AnalyticsView(
                gradebook: gb,
                onStudentTap: (s) =>
                    context.push(Routes.student(widget.courseId, s.id)),
              ),
            ),
          )
        else
          ..._gridSlivers(context, gb),
      ],
    );
  }

  Widget _emptySliver(EdgeInsets padding, Widget child) => SliverPadding(
    padding: padding,
    sliver: SliverToBoxAdapter(child: child),
  );

  List<Widget> _gridSlivers(BuildContext context, Gradebook gb) {
    final l10n = context.l10n;
    final query = _query.trim().toLowerCase();
    final rows = gb
        .sorted(_sort, descending: _descending)
        .where(
          (r) =>
              query.isEmpty ||
              r.student.displayName.toLowerCase().contains(query) ||
              r.student.sortName.toLowerCase().contains(query) ||
              r.student.studentNumber.toLowerCase().contains(query),
        )
        .toList();
    final direction = _descending
        ? l10n.gradebookSortDescending
        : l10n.gradebookSortAscending;
    final arrow = _descending ? Icons.arrow_upward : Icons.arrow_downward;

    Widget sortChip(GradebookSort sort, String label) => Semantics(
      button: true,
      selected: _sort == sort,
      label: _sort == sort
          ? l10n.gradebookSortSemantics(label, direction)
          : label,
      excludeSemantics: true,
      child: RubricChip(
        label: label,
        selected: _sort == sort,
        icon: _sort == sort ? arrow : null,
        onTap: () => _setSort(sort),
      ),
    );

    return [
      SliverPadding(
        padding: Insets.page,
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: Insets.xs,
                runSpacing: Insets.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  sortChip(GradebookSort.name, l10n.gradebookSortName),
                  sortChip(GradebookSort.average, l10n.gradebookSortAverage),
                  const SizedBox(width: Insets.xs),
                  RubricChip(
                    label: l10n.gradebookShowPercent,
                    selected: !_letters,
                    onTap: () => setState(() => _letters = false),
                  ),
                  RubricChip(
                    label: l10n.gradebookShowLetters,
                    selected: _letters,
                    onTap: () => setState(() => _letters = true),
                  ),
                ],
              ),
              if (gb.rows.length > _searchThreshold) ...[
                const SizedBox(height: Insets.md),
                RubricFormWell(
                  child: RubricTextField(
                    hintText: l10n.gradebookSearchHint,
                    textInputAction: TextInputAction.search,
                    textCapitalization: TextCapitalization.none,
                    style: RubricTextStyles.bodySmall,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ],
              const SizedBox(height: Insets.md),
            ],
          ),
        ),
      ),
      if (rows.isEmpty)
        _emptySliver(
          Insets.page,
          EmptyState(title: l10n.gradebookNoMatches(_query.trim())),
        )
      else
        SliverPadding(
          padding: Insets.page,
          sliver: SliverToBoxAdapter(
            child: SizedBox(
              height: _gridHeight(context, rows.length),
              child: GradebookGrid(
                gradebook: gb,
                rows: rows,
                letters: _letters,
                onCellTap: (cell) => context.push(
                  Routes.grade(
                    widget.courseId,
                    cell.assignment.id,
                    cell.studentId,
                  ),
                ),
                onStudentTap: (s) =>
                    context.push(Routes.student(widget.courseId, s.id)),
                onAssignmentTap: (a) =>
                    context.push(Routes.assignment(widget.courseId, a.id)),
              ),
            ),
          ),
        ),
      SliverPadding(
        padding: Insets.page.copyWith(top: Insets.md),
        sliver: const SliverToBoxAdapter(child: TierLegend()),
      ),
    ];
  }

  /// Tall enough for every row when that fits on screen, otherwise most of
  /// the screen so the grid scrolls inside itself with header and footer
  /// pinned.
  double _gridHeight(BuildContext context, int rowCount) {
    const chrome = 76.0 + 56.0 + 2; // header + footer + border
    final natural = chrome + rowCount * 56.0;
    final screen = MediaQuery.sizeOf(context).height;
    final available = (screen * .72).clamp(320.0, double.infinity);
    return natural < available ? natural : available;
  }
}
