import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubric_builder/rubric_draft.dart';
import 'package:rubric/features/rubric_builder/rubric_draft_notifier.dart';
import 'package:rubric/features/rubric_builder/widgets/builder_widgets.dart';
import 'package:rubric/l10n/l10n.dart';

/// "Group N" with the first N not already used by a group.
String nextGroupTitle(AppLocalizations l, List<RubricGroup> groups) {
  final taken = {for (final g in groups) g.title.trim()};
  var n = groups.length + 1;
  while (taken.contains(l.builderGroupDefaultTitle(n))) {
    n++;
  }
  return l.builderGroupDefaultTitle(n);
}

/// Width a dragged card keeps while it follows the finger.
double _dragWidth(BuildContext context) =>
    math.min(MediaQuery.sizeOf(context).width, builderMaxWidth) - 2 * Insets.lg;

/// Where a tapped objective should go, chosen from the move sheet.
typedef _MoveTarget = ({String? groupId, bool newGroup});

/// The tap alternative to dragging: pick a destination from a list.
Future<void> _showMoveSheet(
  BuildContext context,
  WidgetRef ref, {
  required RubricDraft draft,
  required String rubricId,
  required Objective objective,
}) async {
  final l = context.l10n;
  final current = draft.rubric.groupOf(objective.id);
  final target = await showRubricSheet<_MoveTarget>(
    context: context,
    child: RubricSheet(
      title: l.builderMoveTo(objective.title),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in draft.rubric.groups)
            if (g.id != current?.id)
              SheetOption(
                label: g.title.trim().isEmpty
                    ? l.builderUntitledGroup
                    : g.title,
                icon: FontAwesomeIcons.layerGroup,
                value: (groupId: g.id, newGroup: false),
              ),
          SheetOption(
            label: l.builderMoveToNewGroup,
            icon: FontAwesomeIcons.plus,
            value: (groupId: null, newGroup: true),
          ),
          if (current != null)
            SheetOption(
              label: l.builderMoveToTray,
              icon: FontAwesomeIcons.arrowTurnDown,
              value: (groupId: null, newGroup: false),
            ),
        ],
      ),
    ),
  );
  if (target == null || !context.mounted) return;
  final notifier = ref.read(rubricDraftProvider(rubricId).notifier);
  if (target.newGroup) {
    notifier.moveToNewGroup(
      objective.id,
      title: nextGroupTitle(l, draft.rubric.groups),
    );
  } else {
    notifier.moveObjective(objective.id, groupId: target.groupId);
  }
}

/// Step 2: drag objectives into groups (v1 "Assign Groups").
class GroupsStep extends ConsumerWidget {
  const new({
    required this.draft,
    required this.rubricId,
    required this.onEditObjectives,
    super.key,
  });

  final RubricDraft draft;
  final String rubricId;
  final VoidCallback onEditObjectives;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final notifier = ref.read(rubricDraftProvider(rubricId).notifier);
    final groups = draft.rubric.groups;
    final numbers = {
      for (final (i, o) in draft.objectives.indexed) o.id: i + 1,
    };

    if (draft.objectives.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(
          title: l.builderGroupsEmptyTitle,
          message: l.builderGroupsEmptyMessage,
          action: FilledButton(
            onPressed: onEditObjectives,
            child: Text(l.builderGroupsEmptyAction),
          ),
        ),
      );
    }

    final showShortcut = draft.ungrouped.isNotEmpty || groups.length > 1;

    return SliverList.list(
      children: [
        StepIntro(l.builderGroupsIntro),
        if (showShortcut)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Insets.lg),
              child: OutlinedButton.icon(
                icon: const FaIcon(FontAwesomeIcons.layerGroup, size: 16),
                label: Text(l.builderGroupEverything),
                onPressed: () => notifier.groupEverything(
                  title: nextGroupTitle(l, const []),
                ),
              ),
            ),
          ),
        for (final group in groups) ...[
          Row(
            children: [
              Expanded(
                child: DraftField(
                  key: ValueKey('title-${group.id}'),
                  value: group.title,
                  hintText: l.builderGroupTitleHint,
                  semanticLabel: l.builderGroupTitleHint,
                  textInputAction: TextInputAction.done,
                  onChanged: (v) => notifier.renameGroup(group.id, v),
                ),
              ),
              BuilderIconButton(
                icon: FontAwesomeIcons.xmark,
                label: l.builderRemoveGroup(group.title),
                onTap: () => notifier.removeGroup(group.id),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          for (final objective in group.objectives) ...[
            _DraggableObjective(
              objective: objective,
              number: numbers[objective.id]!,
              onTap: () => _showMoveSheet(
                context,
                ref,
                draft: draft,
                rubricId: rubricId,
                objective: objective,
              ),
            ),
            const SizedBox(height: Insets.md),
          ],
          DashedDropTarget<String>(
            label: l.builderAddToGroup(
              group.title.trim().isEmpty ? l.builderUntitledGroup : group.title,
            ),
            canAccept: (id) => group.objectives.every((o) => o.id != id),
            onAccept: (id) => notifier.moveObjective(id, groupId: group.id),
          ),
          const SizedBox(height: Insets.xl),
        ],
        DashedDropTarget<String>(
          label: groups.isEmpty
              ? l.assignGroupsDragMessage
              : l.assignGroupsDragTarget,
          onAccept: (id) =>
              notifier.moveToNewGroup(id, title: nextGroupTitle(l, groups)),
        ),
      ],
    );
  }
}

/// The dock of objectives not yet in a group. Replaces the Next button while
/// it has anything in it; dropping a grouped objective here ungroups it.
///
/// It is the page's docked CTA, so RubricPage's fairway keeps the last drop
/// target clear of it at whatever height it lays out; the step no longer
/// reserves a guessed height of its own.
class UngroupedTray extends ConsumerWidget {
  const new({required this.draft, required this.rubricId, super.key});

  final RubricDraft draft;
  final String rubricId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final notifier = ref.read(rubricDraftProvider(rubricId).notifier);
    final numbers = {
      for (final (i, o) in draft.objectives.indexed) o.id: i + 1,
    };

    return LayoutBuilder(
      builder: (context, constraints) => DragTarget<String>(
        onWillAcceptWithDetails: (d) =>
            draft.ungrouped.every((o) => o.id != d.data),
        onAcceptWithDetails: (d) => notifier.moveObjective(d.data),
        builder: (context, candidates, _) => Container(
          width:
              math.min(constraints.maxWidth, builderMaxWidth) - 2 * Insets.sm,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .45,
          ),
          decoration: BoxDecoration(
            borderRadius: Corners.card,
            color: primaryDark,
            border: Border.all(
              color: candidates.isEmpty ? primaryDark : accent,
              width: 2,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: CardHint(
                    l.builderUngroupedCount(draft.ungrouped.length),
                  ),
                ),
                const SizedBox(height: Insets.md),
                for (final objective in draft.ungrouped) ...[
                  _DraggableObjective(
                    objective: objective,
                    number: numbers[objective.id]!,
                    onTap: () => _showMoveSheet(
                      context,
                      ref,
                      draft: draft,
                      rubricId: rubricId,
                      objective: objective,
                    ),
                  ),
                  const SizedBox(height: Insets.md),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraggableObjective extends StatelessWidget {
  const new({
    required this.objective,
    required this.number,
    required this.onTap,
  });

  final Objective objective;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = RubricCard(
      cardHintText: context.l10n.builderObjectiveHint(number),
      cardTitleText: objective.title,
      titleMaxLines: 2,
      onTap: onTap,
    );
    return LongPressDraggable<String>(
      data: objective.id,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: _dragWidth(context), child: card),
      ),
      childWhenDragging: Opacity(opacity: .4, child: card),
      child: card,
    );
  }
}
