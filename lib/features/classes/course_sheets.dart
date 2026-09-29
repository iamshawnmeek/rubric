import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/features/classes/classes_providers.dart';
import 'package:rubric/features/classes/classes_widgets.dart';
import 'package:rubric/l10n/l10n.dart';

/// Opens the New/Edit class sheet. Saves and resolves to the course, or null
/// when dismissed.
Future<Course?> showCourseSheet(
  BuildContext context,
  WidgetRef ref, {
  Course? course,
}) async {
  final result = await showRubricSheet<Course>(
    context: context,
    child: _CourseForm(course: course),
  );
  if (result != null) {
    await ref.read(courseRepositoryProvider).saveCourse(result);
  }
  return result;
}

class _CourseForm extends StatefulWidget {
  const new({this.course});

  final Course? course;

  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  late final _name = TextEditingController(text: widget.course?.name);
  late final _section = TextEditingController(text: widget.course?.section);
  late final _term = TextEditingController(text: widget.course?.term);

  bool get _valid => _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _section.dispose();
    _term.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_valid) return;
    final name = _name.text.trim();
    final section = _section.text.trim();
    final term = _term.text.trim();
    final existing = widget.course;
    Navigator.of(context).pop(
      existing == null
          ? Course.create(name: name, section: section, term: term)
          : existing.copyWith(name: name, section: section, term: term),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RubricSheet(
      title: widget.course == null
          ? l10n.classesNewClass
          : l10n.classesEditClass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RubricFormWell(
            child: Column(
              children: [
                LabeledField(
                  label: l10n.classesNameLabel,
                  hint: l10n.classesNameHint,
                  controller: _name,
                  autofocus: widget.course == null,
                  onChanged: (_) => setState(() {}),
                ),
                LabeledField(
                  label: l10n.classesSectionLabel,
                  hint: l10n.classesSectionHint,
                  controller: _section,
                  textCapitalization: TextCapitalization.sentences,
                ),
                LabeledField(
                  label: l10n.classesTermLabel,
                  hint: l10n.classesTermHint,
                  controller: _term,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),
          AccentButton(
            label: widget.course == null
                ? l10n.classesCreate
                : l10n.classesSave,
            onTap: _valid ? _submit : null,
            widthFactor: .15,
          ),
        ],
      ),
    );
  }
}

enum CourseAction { edit, archive, restore, delete }

/// The edit / archive / delete menu for a course.
Future<void> showCourseActions(
  BuildContext context,
  WidgetRef ref,
  Course course, {
  VoidCallback? onDeleted,
}) async {
  final l10n = context.l10n;
  final action = await showActionSheet<CourseAction>(
    context,
    title: course.name,
    actions: [
      SheetAction(
        value: CourseAction.edit,
        label: l10n.classesEdit,
        icon: FontAwesomeIcons.pen,
      ),
      if (course.archived)
        SheetAction(
          value: CourseAction.restore,
          label: l10n.classesRestore,
          icon: FontAwesomeIcons.boxOpen,
        )
      else
        SheetAction(
          value: CourseAction.archive,
          label: l10n.classesArchive,
          icon: FontAwesomeIcons.boxArchive,
        ),
      SheetAction(
        value: CourseAction.delete,
        label: l10n.classesDelete,
        icon: FontAwesomeIcons.trashCan,
        destructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case CourseAction.edit:
      await showCourseSheet(context, ref, course: course);
    case CourseAction.archive:
    case CourseAction.restore:
      await setCourseArchived(context, ref, course, archived: !course.archived);
    case CourseAction.delete:
      if (await deleteCourse(context, ref, course)) onDeleted?.call();
  }
}

/// Archives or restores [course], with an Undo on the snackbar.
Future<void> setCourseArchived(
  BuildContext context,
  WidgetRef ref,
  Course course, {
  required bool archived,
}) async {
  final l10n = context.l10n;
  final repo = ref.read(courseRepositoryProvider);
  await repo.saveCourse(course.copyWith(archived: archived));
  if (!context.mounted) return;
  showRubricSnack(
    context,
    archived
        ? l10n.classesArchivedSnack(course.name)
        : l10n.classesRestoredSnack(course.name),
    action: SnackBarAction(
      label: l10n.classesUndo,
      onPressed: () => repo.saveCourse(course),
    ),
  );
}

/// Confirms and deletes [course] with everything in it. A class with grades
/// asks for its name to be typed first. Resolves true when deleted.
Future<bool> deleteCourse(
  BuildContext context,
  WidgetRef ref,
  Course course,
) async {
  final confirmed = await showRubricSheet<bool>(
    context: context,
    child: _DeleteCourseSheet(course: course),
  );
  if (confirmed != true) return false;
  await ref.read(courseRepositoryProvider).deleteCourse(course.id);
  if (context.mounted) {
    showRubricSnack(context, context.l10n.classesDeletedSnack(course.name));
  }
  return true;
}

class _DeleteCourseSheet extends ConsumerStatefulWidget {
  const new({required this.course});

  final Course course;

  @override
  ConsumerState<_DeleteCourseSheet> createState() => _DeleteCourseSheetState();
}

class _DeleteCourseSheetState extends ConsumerState<_DeleteCourseSheet> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool _ready({required bool requireTypedName}) =>
      !requireTypedName ||
      _typed.text.trim().toLowerCase() ==
          widget.course.name.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final id = widget.course.id;
    final active = ref.watch(studentsProvider(id));
    final archived = ref.watch(archivedStudentsProvider(id));
    final assignments = ref.watch(assignmentsProvider(id));
    final evaluations = ref.watch(courseEvaluationsProvider(id));
    final title = context.l10n.classesDeleteTitle(widget.course.name);

    if (active.value == null ||
        archived.value == null ||
        assignments.value == null ||
        evaluations.value == null) {
      final failed = [
        active,
        archived,
        assignments,
        evaluations,
      ].where((v) => v.hasError).firstOrNull;
      return RubricSheet(
        title: title,
        child: AsyncView(
          value: failed ?? const AsyncLoading<Object?>(),
          data: (_) => const SizedBox(),
        ),
      );
    }
    return _buildLoaded(
      context,
      studentCount: active.value!.length + archived.value!.length,
      assignmentCount: assignments.value!.length,
      requireTypedName: hasAnyGrades(evaluations.value!),
    );
  }

  Widget _buildLoaded(
    BuildContext context, {
    required int studentCount,
    required int assignmentCount,
    required bool requireTypedName,
  }) {
    final l10n = context.l10n;
    return RubricSheet(
      title: l10n.classesDeleteTitle(widget.course.name),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.classesDeleteMessage(
              l10n.classesDeleteStudents(studentCount),
              l10n.classesDeleteAssignments(assignmentCount),
            ),
            style: RubricTextStyles.bodySmall.copyWith(color: white),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            l10n.classesDeleteArchiveInstead,
            style: RubricTextStyles.bodySmall,
          ),
          if (requireTypedName) ...[
            const SizedBox(height: Insets.lg),
            RubricFormWell(
              child: LabeledField(
                label: l10n.classesDeleteTypeToConfirm(widget.course.name),
                hint: widget.course.name,
                controller: _typed,
                autofocus: true,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.none,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
          const SizedBox(height: Insets.lg),
          AccentButton(
            label: l10n.classesDeleteConfirm,
            onTap: _ready(requireTypedName: requireTypedName)
                ? () => Navigator.of(context).pop(true)
                : null,
            widthFactor: .15,
          ),
        ],
      ),
    );
  }
}
