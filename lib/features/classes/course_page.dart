import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/features/classes/classes_providers.dart';
import 'package:rubric/features/classes/classes_widgets.dart';
import 'package:rubric/features/classes/course_sheets.dart';
import 'package:rubric/features/classes/student_sheets.dart';
import 'package:rubric/l10n/l10n.dart';

enum _CourseTab { assignments, students }

/// One class: its assignments with grading progress, and its roster.
class CoursePage extends ConsumerStatefulWidget {
  const new({required this.courseId, super.key});

  final String courseId;

  @override
  ConsumerState<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends ConsumerState<CoursePage> {
  _CourseTab _tab = _CourseTab.assignments;

  List<Student> _wholeRoster() => [
    ...?ref.read(studentsProvider(widget.courseId)).value,
    ...?ref.read(archivedStudentsProvider(widget.courseId)).value,
  ];

  Future<void> _addStudent() => showStudentSheet(
    context,
    ref,
    courseId: widget.courseId,
    roster: _wholeRoster(),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final courseAsync = ref.watch(courseProvider(widget.courseId));
    // Kept warm so the roster is ready for duplicate checks in the sheets.
    ref.watch(archivedStudentsProvider(widget.courseId));

    final course = courseAsync.value;
    if (course == null) {
      return ContentWidth(
        child: RubricPage(
          title: courseAsync.isLoading ? '' : l10n.classesTitle,
          children: [
            if (courseAsync.isLoading || courseAsync.hasError)
              AsyncView(value: courseAsync, data: (_) => const SizedBox())
            else
              EmptyState(
                title: l10n.classesCourseNotFound,
                action: AccentButton(
                  label: l10n.classesBackToClasses,
                  onTap: () => context.go(Routes.classes),
                  widthFactor: .2,
                ),
              ),
          ],
        ),
      );
    }

    return ContentWidth(
      child: RubricPage(
        title: course.name,
        subtitle: course.subtitle.isEmpty ? null : course.subtitle,
        actions: [
          HeaderAction(
            icon: FontAwesomeIcons.pen,
            label: l10n.classesEditClass,
            onTap: () => showCourseSheet(context, ref, course: course),
          ),
          HeaderAction(
            icon: FontAwesomeIcons.tableCells,
            label: l10n.classesGradebook,
            onTap: () => context.push(Routes.gradebook(course.id)),
          ),
          HeaderAction(
            icon: FontAwesomeIcons.ellipsisVertical,
            label: l10n.classesMoreActions,
            onTap: () => showCourseActions(
              context,
              ref,
              course,
              onDeleted: () => context.go(Routes.classes),
            ),
          ),
        ],
        bottomCta: switch (_tab) {
          _CourseTab.assignments => AccentButton(
            label: l10n.classesNewAssignment,
            onTap: () => context.push(Routes.newAssignment(course.id)),
            widthFactor: .2,
          ),
          _CourseTab.students => AccentButton(
            label: l10n.classesAddStudent,
            onTap: _addStudent,
            widthFactor: .2,
          ),
        },
        slivers: [
          SliverPadding(
            padding: Insets.page,
            sliver: SliverToBoxAdapter(
              child: SegmentedToggle<_CourseTab>(
                segments: {
                  _CourseTab.assignments: l10n.classesAssignmentsTab,
                  _CourseTab.students: l10n.classesStudentsTab,
                },
                selected: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Insets.lg)),
          SliverPadding(
            padding: Insets.page,
            sliver: switch (_tab) {
              _CourseTab.assignments => _AssignmentsSection(course: course),
              _CourseTab.students => _StudentsSection(
                course: course,
                wholeRoster: _wholeRoster,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _AssignmentsSection extends ConsumerWidget {
  const new({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final assignments = ref.watch(assignmentsProvider(course.id));
    final students = ref.watch(studentsProvider(course.id)).value ?? const [];
    final evaluations =
        ref.watch(courseEvaluationsProvider(course.id)).value ?? const [];
    final studentIds = {for (final s in students) s.id};

    return SliverAsyncView(
      value: assignments,
      data: (list) => list.isEmpty
          ? SliverToBoxAdapter(
              child: EmptyState(
                title: l10n.classesAssignmentsEmptyTitle,
                message: l10n.classesAssignmentsEmptyMessage,
              ),
            )
          : SliverList.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: Insets.sm),
              itemBuilder: (context, i) => _AssignmentCard(
                assignment: list[i],
                progress: gradingProgress(list[i].id, evaluations, studentIds),
              ),
            ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const new({required this.assignment, required this.progress});

  final Assignment assignment;
  final GradingProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final due = assignment.dueDate;
    final locale = Localizations.localeOf(context).toString();
    final progressText = l10n.classesGradedProgress(
      progress.graded,
      progress.total,
    );
    final hint = [
      if (due == null)
        l10n.classesNoDueDate
      else
        l10n.classesDue(DateFormat.MMMd(locale).format(due)),
      if (assignment.closed) l10n.classesClosed,
    ].join(' · ');

    void open() =>
        context.push(Routes.assignment(assignment.courseId, assignment.id));

    return RubricCard(
      semanticValue: progressText,
      cardHintText: hint,
      cardTitleText: assignment.title,
      titleMaxLines: 2,
      onTap: open,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RubricProgressBar(
            value: progress.total == 0 ? 0 : progress.graded / progress.total,
            height: 6,
          ),
          const SizedBox(height: 6),
          // Announced once, as the card's value.
          ExcludeSemantics(
            child: Text(progressText, style: RubricTextStyles.caption),
          ),
        ],
      ),
    );
  }
}

class _StudentsSection extends ConsumerStatefulWidget {
  const new({required this.course, required this.wholeRoster});

  final Course course;
  final List<Student> Function() wholeRoster;

  @override
  ConsumerState<_StudentsSection> createState() => _StudentsSectionState();
}

class _StudentsSectionState extends ConsumerState<_StudentsSection> {
  final _search = TextEditingController();
  String _query = '';
  bool _showArchived = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Student s) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return s.displayName.toLowerCase().contains(q) ||
        s.sortName.toLowerCase().contains(q) ||
        s.studentNumber.toLowerCase().contains(q) ||
        s.email.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final course = widget.course;
    final active = ref.watch(studentsProvider(course.id));
    final archived =
        ref.watch(archivedStudentsProvider(course.id)).value ?? const [];

    final toolbar = Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: [
        PillAction(
          label: l10n.classesPasteNames,
          icon: FontAwesomeIcons.paste,
          onTap: () => showPasteNamesSheet(
            context,
            ref,
            courseId: course.id,
            roster: widget.wholeRoster(),
          ),
        ),
        PillAction(
          label: l10n.classesImportRoster,
          icon: FontAwesomeIcons.fileCsv,
          onTap: () => context.push(Routes.rosterImport(course.id)),
        ),
      ],
    );

    return SliverAsyncView(
      value: active,
      data: (students) {
        final visible = students.where(_matches).toList();
        final visibleArchived = _showArchived
            ? archived.where(_matches).toList()
            : const <Student>[];
        final empty = students.isEmpty && archived.isEmpty;

        return SliverList.list(
          children: [
            toolbar,
            const SizedBox(height: Insets.lg),
            if (empty)
              EmptyState(
                title: l10n.classesStudentsEmptyTitle,
                message: l10n.classesStudentsEmptyMessage,
              )
            else ...[
              _SearchField(
                controller: _search,
                hint: l10n.classesSearchStudents,
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: Insets.sm),
              if (visible.isEmpty && _query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Insets.lg),
                  child: Text(
                    l10n.classesNoSearchResults(_query),
                    textAlign: TextAlign.center,
                    style: RubricTextStyles.bodySmall,
                  ),
                ),
              for (final s in visible)
                _StudentRow(student: s, roster: widget.wholeRoster),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: Insets.sm),
                TextButton(
                  onPressed: () =>
                      setState(() => _showArchived = !_showArchived),
                  child: Text(
                    _showArchived
                        ? l10n.classesHideArchivedStudents
                        : l10n.classesShowArchivedStudents(archived.length),
                  ),
                ),
                for (final s in visibleArchived)
                  _StudentRow(student: s, roster: widget.wholeRoster),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const new({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: primaryDark, borderRadius: Corners.card),
      child: Row(
        children: [
          const FaIcon(
            FontAwesomeIcons.magnifyingGlass,
            color: primaryLight,
            size: 16,
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: RubricTextField(
              controller: controller,
              hintText: hint,
              onChanged: onChanged,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.search,
              style: RubricTextStyles.bodySmall,
              hintStyle: RubricTextStyles.bodySmall.copyWith(color: inactive),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentRow extends ConsumerWidget {
  const new({required this.student, required this.roster});

  final Student student;
  final List<Student> Function() roster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final meta = [
      if (student.archived) l10n.classesArchivedTag,
      if (student.studentNumber.isNotEmpty)
        l10n.classesStudentNumberTag(student.studentNumber),
      if (student.email.isNotEmpty) student.email,
    ].join(' · ');
    void actions() =>
        showStudentActions(context, ref, student: student, roster: roster());

    return Row(
      key: ValueKey(student.id),
      children: [
        Expanded(
          child: MergeSemantics(
            child: InkWell(
              borderRadius: Corners.card,
              onTap: () =>
                  context.push(Routes.student(student.courseId, student.id)),
              onLongPress: actions,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Row(
                  children: [
                    InitialsAvatar(student.initials, faded: student.archived),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            student.sortName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RubricTextStyles.listTitle.copyWith(
                              color: student.archived ? primaryLight : white,
                            ),
                          ),
                          if (meta.isNotEmpty)
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: RubricTextStyles.caption,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.classesActionsFor(student.displayName),
          onPressed: actions,
          icon: const FaIcon(
            FontAwesomeIcons.ellipsisVertical,
            color: primaryLighter,
            size: 18,
          ),
        ),
      ],
    );
  }
}
