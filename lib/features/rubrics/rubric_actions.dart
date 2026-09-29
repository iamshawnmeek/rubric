import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/export/export_actions.dart';
import 'package:rubric/features/rubric_builder/rubric_builder_page.dart'
    show BuilderStep;
import 'package:rubric/features/rubrics/library_filter.dart';
import 'package:rubric/features/rubrics/rubric_labels.dart';
import 'package:rubric/l10n/l10n.dart';

/// Archived library rubrics, most recently edited first.
final archivedRubricsProvider = StreamProvider<List<Rubric>>(
  (ref) => ref.watch(rubricRepositoryProvider).watchAll(archived: true),
);

/// What the library, detail page and gallery can do to a rubric. Each action
/// reports its outcome in a snack, with undo where it is cheap.
///
/// The messenger and router are captured before any await: the widget that
/// triggered an action (a list item) is often gone by the time it completes.
abstract final class RubricActions {
  static Future<void> edit(BuildContext context, Rubric rubric) =>
      context.push(Routes.buildRubric(rubric.id));

  static Future<void> duplicate(
    BuildContext context,
    WidgetRef ref,
    Rubric rubric,
  ) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final copy = rubric.duplicate(title: l.rubricsCopyTitle(l.titleOf(rubric)));
    await ref.read(rubricRepositoryProvider).save(copy);
    _snack(
      messenger,
      l.rubricsDuplicated(l.titleOf(rubric)),
      SnackBarAction(
        label: l.rubricsOpen,
        onPressed: () => router.push(Routes.rubric(copy.id)),
      ),
    );
  }

  static Future<void> saveAsTemplate(
    BuildContext context,
    WidgetRef ref,
    Rubric rubric,
  ) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    await ref
        .read(rubricRepositoryProvider)
        .save(rubric.duplicate(isTemplate: true));
    _snack(
      messenger,
      l.rubricsSavedAsTemplate(l.titleOf(rubric)),
      SnackBarAction(
        label: l.rubricsView,
        onPressed: () => router.push(Routes.templates),
      ),
    );
  }

  static Future<void> setArchived(
    BuildContext context,
    WidgetRef ref,
    Rubric rubric, {
    required bool archived,
  }) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(rubricRepositoryProvider);
    await repo.setArchived(rubric.id, archived: archived);
    _snack(
      messenger,
      archived
          ? l.rubricsArchived(l.titleOf(rubric))
          : l.rubricsUnarchived(l.titleOf(rubric)),
      SnackBarAction(
        label: l.rubricsUndo,
        onPressed: () => repo.setArchived(rubric.id, archived: !archived),
      ),
    );
  }

  /// Confirms, then deletes [rubric]. The confirmation says how many
  /// assignments were built from it — they keep their own snapshot, so
  /// deleting is safe. Resolves true when the rubric was deleted.
  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref,
    Rubric rubric,
  ) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(rubricRepositoryProvider);
    final title = l.titleOf(rubric);
    final assignments = await ref.read(assignmentRepositoryProvider).all();
    final used = usageCount(assignments, rubric.id);
    if (!context.mounted) return false;
    final confirmed = await confirm(
      context,
      title: l.rubricsDeleteTitle,
      message: used == 0
          ? l.rubricsDeleteMessage(title)
          : l.rubricsDeleteUsedMessage(title, used),
      confirmLabel: l.rubricsDeleteConfirm,
    );
    if (!confirmed) return false;

    await repo.delete(rubric.id);
    _snack(
      messenger,
      l.rubricsDeleted(title),
      SnackBarAction(
        label: l.rubricsUndo,
        // Restore exactly, including when it was last edited.
        onPressed: () => repo.save(rubric, now: rubric.updatedAt),
      ),
    );
    return true;
  }

  /// Copies [template] into the library as an ordinary rubric with fresh ids,
  /// then opens the builder on its review step.
  static Future<void> useTemplate(
    BuildContext context,
    WidgetRef ref,
    Rubric template,
  ) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final copy = template.duplicate(isTemplate: false);
    await ref.read(rubricRepositoryProvider).save(copy);
    _snack(messenger, l.rubricsTemplateAdded(l.titleOf(template)));
    await router.push(Routes.buildRubric(copy.id, step: BuilderStep.review));
  }

  static void _snack(
    ScaffoldMessengerState messenger,
    String message, [
    SnackBarAction? action,
  ]) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }
}

enum _MenuAction { edit, duplicate, print, saveAsTemplate, archive, delete }

/// The overflow menu for a stored rubric (library item or detail page).
class RubricMenuButton extends ConsumerWidget {
  const new({
    required this.rubric,
    this.showEdit = true,
    this.showPrint = false,
    this.onDeleted,
    super.key,
  });

  final Rubric rubric;
  final bool showEdit;
  final bool showPrint;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    PopupMenuItem<_MenuAction> item(
      _MenuAction value,
      FaIconData icon,
      String label,
    ) => PopupMenuItem(
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: FaIcon(icon, size: 16, color: primaryLighter),
          ),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );

    return PopupMenuButton<_MenuAction>(
      tooltip: l.rubricsMoreActions(l.titleOf(rubric)),
      icon: const FaIcon(
        FontAwesomeIcons.ellipsisVertical,
        color: primaryLightest,
        size: 20,
      ),
      onSelected: (action) async {
        switch (action) {
          case _MenuAction.edit:
            await RubricActions.edit(context, rubric);
          case _MenuAction.duplicate:
            await RubricActions.duplicate(context, ref, rubric);
          case _MenuAction.print:
            await exportRubricPdf(context, rubric);
          case _MenuAction.saveAsTemplate:
            await RubricActions.saveAsTemplate(context, ref, rubric);
          case _MenuAction.archive:
            await RubricActions.setArchived(
              context,
              ref,
              rubric,
              archived: !rubric.archived,
            );
          case _MenuAction.delete:
            if (await RubricActions.delete(context, ref, rubric)) {
              onDeleted?.call();
            }
        }
      },
      itemBuilder: (context) => [
        if (showEdit)
          item(_MenuAction.edit, FontAwesomeIcons.pen, l.rubricsActionEdit),
        item(
          _MenuAction.duplicate,
          FontAwesomeIcons.copy,
          l.rubricsActionDuplicate,
        ),
        if (showPrint)
          item(_MenuAction.print, FontAwesomeIcons.print, l.rubricsActionPrint),
        if (!rubric.isTemplate) ...[
          item(
            _MenuAction.saveAsTemplate,
            FontAwesomeIcons.shapes,
            l.rubricsActionSaveAsTemplate,
          ),
          item(
            _MenuAction.archive,
            rubric.archived
                ? FontAwesomeIcons.boxOpen
                : FontAwesomeIcons.boxArchive,
            rubric.archived ? l.rubricsActionUnarchive : l.rubricsActionArchive,
          ),
        ],
        item(
          _MenuAction.delete,
          FontAwesomeIcons.trashCan,
          l.rubricsActionDelete,
        ),
      ],
    );
  }
}
