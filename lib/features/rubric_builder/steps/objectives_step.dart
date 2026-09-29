import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubric_builder/rubric_draft.dart';
import 'package:rubric/features/rubric_builder/rubric_draft_notifier.dart';
import 'package:rubric/features/rubric_builder/widgets/builder_widgets.dart';
import 'package:rubric/features/rubric_builder/widgets/objective_sheet.dart';
import 'package:rubric/l10n/l10n.dart';

/// Step 1: the list of objectives. Tap to edit, swipe to delete (with undo),
/// drag the grip to reorder, long-press for the same actions in a menu.
class ObjectivesStep extends ConsumerWidget {
  const new({required this.draft, required this.rubricId, super.key});

  final RubricDraft draft;
  final String rubricId;

  RubricDraftNotifier _notifier(WidgetRef ref) =>
      ref.read(rubricDraftProvider(rubricId).notifier);

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final input = await showObjectiveSheet(context);
    if (input == null || !context.mounted) return;
    _notifier(ref).addObjective(input.title, description: input.description);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Objective objective,
  ) async {
    final input = await showObjectiveSheet(context, editing: objective);
    if (input == null || !context.mounted) return;
    _notifier(ref).updateObjective(
      objective.id,
      title: input.title,
      description: input.description,
    );
  }

  void _delete(BuildContext context, WidgetRef ref, Objective objective) {
    final notifier = _notifier(ref);
    final removed = notifier.removeObjective(objective.id);
    if (removed == null) return;
    showRubricSnack(
      context,
      context.l10n.builderObjectiveDeleted(objective.title),
      action: SnackBarAction(
        label: context.l10n.builderUndo,
        onPressed: () => notifier.restoreObjective(removed),
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    Objective objective,
    int index,
  ) async {
    final l = context.l10n;
    final count = draft.objectives.length;
    final action = await showRubricSheet<_Action>(
      context: context,
      child: RubricSheet(
        title: objective.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetOption(
              icon: FontAwesomeIcons.pen,
              label: l.builderEdit,
              value: _Action.edit,
            ),
            if (index > 0)
              SheetOption(
                icon: FontAwesomeIcons.arrowUp,
                label: l.builderMoveUp,
                value: _Action.up,
              ),
            if (index < count - 1)
              SheetOption(
                icon: FontAwesomeIcons.arrowDown,
                label: l.builderMoveDown,
                value: _Action.down,
              ),
            SheetOption(
              icon: FontAwesomeIcons.trashCan,
              label: l.builderDelete,
              value: _Action.delete,
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _Action.edit:
        await _edit(context, ref, objective);
      case _Action.up:
        _notifier(ref).reorderObjective(index, index - 1);
      case _Action.down:
        _notifier(ref).reorderObjective(index, index + 1);
      case _Action.delete:
        _delete(context, ref, objective);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final objectives = draft.objectives;

    return SliverMainAxisGroup(
      slivers: [
        if (objectives.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              title: l.builderObjectivesEmptyTitle,
              message: l.builderObjectivesEmptyMessage,
            ),
          ),
        SliverReorderableList(
          itemCount: objectives.length,
          onReorderItem: _notifier(ref).reorderObjective,
          proxyDecorator: (child, _, _) =>
              Material(color: Colors.transparent, child: child),
          itemBuilder: (context, i) {
            final objective = objectives[i];
            final group = draft.rubric.groupOf(objective.id);
            return Padding(
              key: ValueKey(objective.id),
              padding: const EdgeInsets.only(bottom: Insets.md),
              child: Dismissible(
                key: ValueKey('dismiss-${objective.id}'),
                direction: DismissDirection.endToStart,
                background: _DeleteBackground(label: l.builderDelete),
                onDismissed: (_) => _delete(context, ref, objective),
                child: RubricCard(
                  cardHintText: l.builderObjectiveHint(i + 1),
                  cardTitleText: objective.title,
                  onTap: () => _edit(context, ref, objective),
                  onLongPress: () => _showActions(context, ref, objective, i),
                  footer: _footer(objective, group, l),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Semantics(
                      label: l.builderReorderHandle(objective.title),
                      child: const SizedBox(
                        width: Sizes.minTap,
                        height: Sizes.minTap,
                        child: Center(
                          child: FaIcon(
                            FontAwesomeIcons.gripLines,
                            color: primaryLight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        SliverToBoxAdapter(
          child: CreateCard(
            label: l.builderAddObjective,
            onPressed: () => _add(context, ref),
          ),
        ),
      ],
    );
  }

  Widget? _footer(Objective objective, RubricGroup? group, AppLocalizations l) {
    final lines = [
      if (objective.description.isNotEmpty) objective.description,
      if (group != null) l.builderObjectiveInGroup(group.title),
    ];
    if (lines.isEmpty) return null;
    return Text(
      lines.join('\n'),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: RubricTextStyles.bodySmall,
    );
  }
}

enum _Action { edit, up, down, delete }

class _DeleteBackground extends StatelessWidget {
  const new({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      decoration: BoxDecoration(color: primaryDark, borderRadius: Corners.card),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: RubricTextStyles.listTitle),
          const SizedBox(width: Insets.sm),
          const FaIcon(FontAwesomeIcons.trashCan, color: accent),
        ],
      ),
    );
  }
}
