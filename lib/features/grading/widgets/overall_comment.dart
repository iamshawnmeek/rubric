import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/features/grading/comment_bank_logic.dart';
import 'package:rubric/features/grading/grading_controller.dart';
import 'package:rubric/features/grading/grading_logic.dart';
import 'package:rubric/features/grading/widgets/grading_actions.dart';
import 'package:rubric/features/grading/widgets/synced_text_field.dart';
import 'package:rubric/l10n/l10n.dart';

/// The overall feedback well, with the comment bank beneath it.
class OverallComment extends ConsumerWidget {
  const new({required this.args, required this.comment, super.key});

  final GradingArgs args;
  final String comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final canSave = comment.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RubricFormWell(
          minHeight: 120,
          child: SyncedTextField(
            value: comment,
            hintText: l10n.gradingCommentHint,
            semanticLabel: l10n.gradingCommentSection,
            style: RubricTextStyles.bodySmall.copyWith(fontSize: 18),
            maxLines: null,
            minLines: 3,
            onChanged: (text) => ref.gradeEdit(
              args,
              (_, e) => GradingLogic.setComment(e, text),
              coalesce: 'comment',
            ),
          ),
        ),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.xs,
          children: [
            OutlinedButton.icon(
              onPressed: () => showCommentBankPicker(context, args),
              icon: const FaIcon(FontAwesomeIcons.bookOpen, size: 16),
              label: Text(l10n.gradingCommentBankOpen),
            ),
            TextButton.icon(
              onPressed: canSave ? () => _saveToBank(context, ref) : null,
              icon: const FaIcon(FontAwesomeIcons.bookmark, size: 16),
              label: Text(l10n.gradingCommentSaveToBank),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _saveToBank(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final repo = ref.read(commentRepositoryProvider);
    final existing = await repo.all();
    if (CommentBankLogic.contains(existing, comment)) {
      if (context.mounted) {
        showRubricSnack(context, l10n.gradingCommentAlreadySaved);
      }
      return;
    }
    await repo.save(CommentSnippet.create(comment.trim()));
    if (context.mounted) showRubricSnack(context, l10n.gradingCommentSaved);
  }
}

/// A searchable sheet of the teacher's snippets; tapping one appends it to
/// the current student's overall comment and counts the use.
Future<void> showCommentBankPicker(BuildContext context, GradingArgs args) =>
    showRubricSheet<void>(
      context: context,
      child: _CommentBankPicker(args: args),
    );

class _CommentBankPicker extends ConsumerStatefulWidget {
  const new({required this.args});

  final GradingArgs args;

  @override
  ConsumerState<_CommentBankPicker> createState() => _CommentBankPickerState();
}

class _CommentBankPickerState extends ConsumerState<_CommentBankPicker> {
  String _query = '';

  Future<void> _insert(CommentSnippet s) async {
    ref.gradeEdit(
      widget.args,
      (_, e) => GradingLogic.setComment(
        e,
        GradingLogic.insertSnippet(e.comment, s.text),
      ),
      haptic: true,
    );
    Navigator.of(context).pop();
    await ref.read(commentRepositoryProvider).recordUse(s.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snippets = ref.watch(commentSnippetsProvider);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .75,
      ),
      child: RubricSheet(
        title: l10n.gradingBankTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RubricFormWell(
              child: RubricTextField(
                hintText: l10n.commentBankSearch,
                style: RubricTextStyles.bodySmall.copyWith(fontSize: 18),
                hintStyle: RubricTextStyles.bodySmall.copyWith(fontSize: 18),
                textInputAction: TextInputAction.search,
                onChanged: (q) => setState(() => _query = q),
              ),
            ),
            const SizedBox(height: Insets.md),
            AsyncView(
              value: snippets,
              data: (all) {
                if (all.isEmpty) {
                  return EmptyState(
                    title: l10n.commentBankEmptyTitle,
                    message: l10n.gradingBankEmptyMessage,
                  );
                }
                final shown = CommentBankLogic.filter(all, _query);
                if (shown.isEmpty) {
                  return EmptyState(title: l10n.commentBankNoMatches(_query));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in shown) ...[
                      SnippetTile(snippet: s, onTap: () => _insert(s)),
                      const SizedBox(height: Insets.xs),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One snippet: category hint over the text, with its use count.
class SnippetTile extends StatelessWidget {
  const new({
    required this.snippet,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    super.key,
  });

  final CommentSnippet snippet;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hint = [
      if (snippet.category.trim().isNotEmpty) snippet.category.trim(),
      l10n.commentBankUses(snippet.useCount),
    ].join(' · ');
    return Semantics(
      button: true,
      label: '${snippet.text}. $hint',
      excludeSemantics: true,
      child: Material(
        color: primaryCard,
        borderRadius: Corners.card,
        child: InkWell(
          borderRadius: Corners.card,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            constraints: const BoxConstraints(minHeight: Sizes.minTap),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CardHint(hint, fontSize: 14),
                      const SizedBox(height: 4),
                      Text(
                        snippet.text,
                        style: RubricTextStyles.bodySmall.copyWith(
                          color: white,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
