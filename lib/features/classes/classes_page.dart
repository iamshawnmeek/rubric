import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/features/classes/classes_providers.dart';
import 'package:rubric/features/classes/classes_widgets.dart';
import 'package:rubric/features/classes/course_sheets.dart';
import 'package:rubric/l10n/l10n.dart';

/// The Classes tab: every active course as a card, an archived view, and the
/// New Class sheet.
class ClassesPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends ConsumerState<ClassesPage> {
  bool _archived = false;

  Future<void> _newClass() async {
    final course = await showCourseSheet(context, ref);
    if (course != null && mounted) {
      await context.push(Routes.course(course.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final courses = ref.watch(
      _archived ? archivedCoursesProvider : coursesProvider,
    );
    final counts = ref.watch(studentCountsProvider).value ?? const {};

    return ContentWidth(
      child: RubricPage(
        title: l10n.classesTitle,
        bottomCta: _archived
            ? null
            : AccentButton(
                label: l10n.classesNewClass,
                onTap: _newClass,
                widthFactor: .2,
              ),
        slivers: [
          SliverPadding(
            padding: Insets.page,
            sliver: SliverToBoxAdapter(
              child: SegmentedToggle<bool>(
                segments: {
                  false: l10n.classesActive,
                  true: l10n.classesArchived,
                },
                selected: _archived,
                onChanged: (v) => setState(() => _archived = v),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Insets.lg)),
          SliverPadding(
            padding: Insets.page,
            sliver: SliverAsyncView(
              value: courses,
              data: (list) => list.isEmpty
                  ? SliverToBoxAdapter(
                      child: _archived
                          ? EmptyState(
                              title: l10n.classesArchivedEmptyTitle,
                              message: l10n.classesArchivedEmptyMessage,
                            )
                          : EmptyState(
                              title: l10n.classesEmptyTitle,
                              message: l10n.classesEmptyMessage,
                            ),
                    )
                  : SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Insets.sm),
                      itemBuilder: (context, i) => _CourseCard(
                        course: list[i],
                        students: counts[list[i].id] ?? 0,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends ConsumerWidget {
  const new({required this.course, required this.students});

  final Course course;
  final int students;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hint = [
      if (course.subtitle.isNotEmpty) course.subtitle,
      l10n.classesStudentCount(students),
    ].join(' · ');

    void open() => context.push(Routes.course(course.id));
    void actions() => showCourseActions(context, ref, course);

    // RubricCard hides its InkWell from semantics; restore the actions here
    // (this Semantics merges into the card's node).
    return Semantics(
      key: ValueKey(course.id),
      onTap: open,
      onLongPress: actions,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.classesActionsFor(course.name)):
            actions,
      },
      child: RubricCard(
        cardHintText: hint,
        cardTitleText: course.name,
        titleMaxLines: 2,
        color: course.archived ? primaryDark : primaryCard,
        onTap: open,
        onLongPress: actions,
        trailing: IconButton(
          tooltip: l10n.classesActionsFor(course.name),
          constraints: const BoxConstraints.tightFor(
            width: Sizes.minTap,
            height: Sizes.minTap,
          ),
          onPressed: actions,
          icon: const FaIcon(
            FontAwesomeIcons.ellipsisVertical,
            color: primaryLighter,
            size: 20,
          ),
        ),
      ),
    );
  }
}
