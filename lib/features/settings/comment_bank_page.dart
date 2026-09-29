import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/features/grading/comment_bank_logic.dart';
import 'package:rubric/features/grading/widgets/overall_comment.dart';
import 'package:rubric/l10n/l10n.dart';

/// The teacher's reusable feedback: search, filter by category, add, edit
/// and delete. Most-used snippets come first.
class CommentBankPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<CommentBankPage> createState() => _CommentBankPageState();
}

class _CommentBankPageState extends ConsumerState<CommentBankPage> {
  String _query = '';

  /// null = all categories; '' = uncategorised.
  String? _category;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snippets = ref.watch(commentSnippetsProvider);

    return RubricPage(
      title: l10n.commentBankTitle,
      slivers: [
        SliverPadding(
          padding: Insets.page,
          sliver: SliverAsyncView(
            value: snippets,
            data: (all) => SliverList.list(children: _content(context, all)),
          ),
        ),
      ],
      bottomCta: AccentButton(
        label: l10n.commentBankAdd,
        widthFactor: .2,
        onTap: () => _edit(context, null),
      ),
    );
  }

  List<Widget> _content(BuildContext context, List<CommentSnippet> all) {
    final l10n = context.l10n;
    if (all.isEmpty) {
      return [
        EmptyState(
          title: l10n.commentBankEmptyTitle,
          message: l10n.commentBankEmptyMessage,
        ),
      ];
    }
    final categories = CommentBankLogic.categories(all);
    final hasUncategorised = all.any((s) => s.category.trim().isEmpty);
    // A filter whose last snippet was deleted falls back to "All".
    final category =
        _category == null ||
            categories.contains(_category) ||
            (_category == '' && hasUncategorised)
        ? _category
        : null;
    final shown = CommentBankLogic.filter(all, _query, category: category);

    return [
      RubricFormWell(
        child: RubricTextField(
          hintText: l10n.commentBankSearch,
          style: RubricTextStyles.bodySmall.copyWith(fontSize: 18),
          hintStyle: RubricTextStyles.bodySmall.copyWith(fontSize: 18),
          textInputAction: TextInputAction.search,
          onChanged: (q) => setState(() => _query = q),
        ),
      ),
      if (categories.isNotEmpty) ...[
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.xs,
          runSpacing: Insets.xs,
          children: [
            _CategoryChip(
              label: l10n.commentBankAllCategories,
              selected: category == null,
              onTap: () => setState(() => _category = null),
            ),
            for (final c in categories)
              _CategoryChip(
                label: c,
                selected: category == c,
                onTap: () => setState(() => _category = c),
              ),
            if (hasUncategorised)
              _CategoryChip(
                label: l10n.commentBankUncategorised,
                selected: category == '',
                onTap: () => setState(() => _category = ''),
              ),
          ],
        ),
      ],
      const SizedBox(height: Insets.lg),
      if (shown.isEmpty)
        EmptyState(title: l10n.commentBankNoMatches(_query))
      else
        for (final s in shown) ...[
          SnippetTile(
            key: ValueKey(s.id),
            snippet: s,
            onTap: () => _edit(context, s),
            onLongPress: () => _delete(context, s),
            trailing: IconButton(
              tooltip: l10n.commentBankDelete,
              onPressed: () => _delete(context, s),
              icon: const FaIcon(
                FontAwesomeIcons.trashCan,
                size: 18,
                color: primaryLighter,
              ),
            ),
          ),
          const SizedBox(height: Insets.sm),
        ],
    ];
  }

  Future<void> _edit(BuildContext context, CommentSnippet? existing) =>
      showRubricSheet<void>(
        context: context,
        child: _SnippetEditor(
          existing: existing,
          categories: CommentBankLogic.categories(
            ref.read(commentSnippetsProvider).value ?? const [],
          ),
        ),
      );

  Future<void> _delete(BuildContext context, CommentSnippet s) async {
    final l10n = context.l10n;
    final ok = await confirm(
      context,
      title: l10n.commentBankDeleteTitle,
      message: l10n.commentBankDeleteMessage,
      confirmLabel: l10n.commentBankDelete,
    );
    if (!ok) return;
    final repo = ref.read(commentRepositoryProvider);
    await repo.delete(s.id);
    if (!context.mounted) return;
    showRubricSnack(
      context,
      l10n.commentBankDeleted,
      action: SnackBarAction(
        label: l10n.commentBankUndo,
        onPressed: () => repo.save(s),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const new({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    excludeFromSemantics: true,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Sizes.minTap),
      child: Center(
        widthFactor: 1,
        child: RubricChip(
          label: label,
          selected: selected,
          icon: selected ? Icons.check : null,
          onTap: onTap,
        ),
      ),
    ),
  );
}

class _SnippetEditor extends ConsumerStatefulWidget {
  const new({required this.existing, required this.categories});

  final CommentSnippet? existing;
  final List<String> categories;

  @override
  ConsumerState<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends ConsumerState<_SnippetEditor> {
  late final _text = TextEditingController(text: widget.existing?.text);
  late final _category = TextEditingController(text: widget.existing?.category);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final category = _category.text.trim();
    final existing = widget.existing;
    final snippet = existing == null
        ? CommentSnippet.create(text, category: category)
        : existing.copyWith(text: text, category: category);
    await ref.read(commentRepositoryProvider).save(snippet);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return RubricSheet(
      title: widget.existing == null
          ? l10n.commentBankNewTitle
          : l10n.commentBankEditTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RubricFormWell(
            minHeight: 120,
            child: RubricTextField(
              controller: _text,
              hintText: l10n.commentBankTextHint,
              autofocus: widget.existing == null,
              maxLines: null,
              minLines: 3,
              style: RubricTextStyles.bodySmall.copyWith(fontSize: 18),
              hintStyle: RubricTextStyles.bodySmall.copyWith(fontSize: 18),
            ),
          ),
          const SizedBox(height: Insets.sm),
          RubricFormWell(
            child: RubricTextField(
              controller: _category,
              hintText: l10n.commentBankCategoryHint,
              style: RubricTextStyles.bodySmall.copyWith(fontSize: 18),
              hintStyle: RubricTextStyles.bodySmall.copyWith(fontSize: 18),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
          ),
          if (widget.categories.isNotEmpty) ...[
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.xs,
              runSpacing: Insets.xs,
              children: [
                for (final c in widget.categories)
                  _CategoryChip(
                    label: c,
                    selected: _category.text.trim() == c,
                    onTap: () => setState(() => _category.text = c),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Insets.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _text.text.trim().isEmpty ? null : _save,
              child: Text(l10n.commentBankSave),
            ),
          ),
        ],
      ),
    );
  }
}
