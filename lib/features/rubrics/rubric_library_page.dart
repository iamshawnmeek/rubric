import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/rubrics/builtin_templates.dart';
import 'package:rubric/features/rubrics/library_filter.dart';
import 'package:rubric/features/rubrics/rubric_actions.dart';
import 'package:rubric/features/rubrics/rubric_labels.dart';
import 'package:rubric/l10n/l10n.dart';

/// Every rubric the teacher has built, newest edit first, with search,
/// subject filters and an archive.
class RubricLibraryPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<RubricLibraryPage> createState() => _RubricLibraryPageState();
}

class _RubricLibraryPageState extends ConsumerState<RubricLibraryPage> {
  final _search = TextEditingController();
  String? _subject;
  bool _showArchived = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _search.clear();
    _subject = null;
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rubrics = ref.watch(rubricsProvider);
    final archived = ref.watch(archivedRubricsProvider).value ?? const [];

    return RubricsContentWidth(
      child: RubricPage(
        title: l.rubricsLibraryTitle,
        actions: [
          HeaderAction(
            icon: FontAwesomeIcons.shapes,
            label: l.rubricsTemplatesTitle,
            onTap: () => context.push(Routes.templates),
          ),
        ],
        bottomCta: AccentButton(
          label: l.rubricsNewRubric,
          widthFactor: .2,
          onTap: () => context.push(Routes.buildRubric('new')),
        ),
        slivers: [
          SliverPadding(
            padding: Insets.page,
            sliver: SliverAsyncView(
              value: rubrics,
              data: (active) => SliverList.list(
                children: active.isEmpty && archived.isEmpty
                    ? _empty(context)
                    : _library(context, active, archived),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _empty(BuildContext context) {
    final l = context.l10n;
    return [
      EmptyState(title: l.rubricsEmptyTitle, message: l.rubricsEmptyMessage),
      const _TemplatesEntry(),
    ];
  }

  List<Widget> _library(
    BuildContext context,
    List<Rubric> active,
    List<Rubric> archived,
  ) {
    final l = context.l10n;
    final subjects = subjectsOf([...active, ...archived]);
    // A filter chip can outlive its last rubric (deleted, renamed).
    final subject = subjects.contains(_subject) ? _subject : null;
    final shown = filterRubrics(active, query: _search.text, subject: subject);
    final shownArchived = filterRubrics(
      archived,
      query: _search.text,
      subject: subject,
    );
    final filtering = _search.text.trim().isNotEmpty || subject != null;

    return [
      TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        style: RubricTextStyles.bodySmall.copyWith(color: white),
        cursorColor: accent,
        keyboardAppearance: Brightness.dark,
        decoration: InputDecoration(
          hintText: l.rubricsSearchHint,
          prefixIcon: const Padding(
            padding: EdgeInsets.all(14),
            child: FaIcon(
              FontAwesomeIcons.magnifyingGlass,
              size: 16,
              color: primaryLighter,
            ),
          ),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: l.rubricsClearSearch,
                  onPressed: () => setState(_search.clear),
                  icon: const FaIcon(
                    FontAwesomeIcons.xmark,
                    size: 16,
                    color: primaryLighter,
                  ),
                ),
        ),
      ),
      if (subjects.isNotEmpty) ...[
        const SizedBox(height: Insets.xs),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: l.rubricsFilterAll,
                selected: subject == null,
                onTap: () => setState(() => _subject = null),
              ),
              for (final s in subjects)
                _FilterChip(
                  label: s,
                  selected: subject == s,
                  onTap: () =>
                      setState(() => _subject = subject == s ? null : s),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: Insets.sm),
      if (!filtering) ...[
        const _TemplatesEntry(),
        const SizedBox(height: Insets.lg),
      ],
      if (shown.isEmpty && filtering)
        EmptyState(
          title: l.rubricsNoMatchesTitle,
          message: l.rubricsNoMatchesMessage,
          action: OutlinedButton(
            onPressed: _clearFilters,
            child: Text(l.rubricsClearFilters),
          ),
        ),
      for (final rubric in shown) ...[
        _LibraryCard(rubric: rubric),
        const SizedBox(height: Insets.sm),
      ],
      if (archived.isNotEmpty) ...[
        SectionLabel(
          l.rubricsArchivedSection(archived.length),
          trailing: Semantics(
            label: l.rubricsShowArchived,
            child: Switch(
              value: _showArchived,
              onChanged: (v) => setState(() => _showArchived = v),
            ),
          ),
        ),
        if (_showArchived)
          for (final rubric in shownArchived) ...[
            _LibraryCard(rubric: rubric),
            const SizedBox(height: Insets.sm),
          ],
      ],
    ];
  }
}

/// A [RubricChip] padded out to a 48pt tap target.
class _FilterChip extends StatelessWidget {
  const new({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: Insets.xs, top: 7, bottom: 7),
        child: RubricChip(label: label, selected: selected, onTap: onTap),
      ),
    );
  }
}

class _TemplatesEntry extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return RubricCard(
      color: primaryDark,
      cardHintText: l.rubricsTemplateCount(builtinTemplates.length),
      cardTitleText: l.rubricsStartFromTemplate,
      trailing: const CardChevron(),
      onTap: () => context.push(Routes.templates),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const new({required this.rubric});

  final Rubric rubric;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // The menu sits over the card rather than inside it: RubricCard merges
    // its contents into one semantics node, which would hide the menu.
    return Opacity(
      opacity: rubric.archived ? .7 : 1,
      child: Stack(
        children: [
          RubricCard(
            cardHintText: l.rubricHint(rubric),
            cardTitleText: l.titleOf(rubric),
            titleMaxLines: 2,
            trailing: const SizedBox(width: Sizes.minTap - Insets.sm),
            footer: rubric.isReady
                ? null
                : Text(
                    l.rubricsDraft,
                    style: RubricTextStyles.caption.copyWith(color: accent),
                  ),
            onTap: () => context.push(Routes.rubric(rubric.id)),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 4,
            child: Center(child: RubricMenuButton(rubric: rubric)),
          ),
        ],
      ),
    );
  }
}
