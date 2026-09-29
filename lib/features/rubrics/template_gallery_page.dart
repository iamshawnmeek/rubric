import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/features/rubrics/builtin_templates.dart';
import 'package:rubric/features/rubrics/library_filter.dart';
import 'package:rubric/features/rubrics/rubric_labels.dart';
import 'package:rubric/l10n/l10n.dart';

/// The built-in template catalogue grouped by subject, plus the teacher's own
/// saved templates. Tapping one previews it on the detail page.
class TemplateGalleryPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<TemplateGalleryPage> createState() =>
      _TemplateGalleryPageState();
}

class _TemplateGalleryPageState extends ConsumerState<TemplateGalleryPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final query = _search.text;
    final mine = filterRubrics(
      ref.watch(templatesProvider).value ?? const [],
      query: query,
    );
    final bySubject = groupBy(
      builtinTemplates.where(
        (t) => matchesQuery(t.rubric, query, extra: t.grades),
      ),
      (t) => t.rubric.subject,
    );
    final subjects = bySubject.keys.sorted();

    return RubricsContentWidth(
      child: RubricPage(
        title: l.rubricsTemplatesTitle,
        subtitle: l.rubricsTemplatesSubtitle,
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            style: RubricTextStyles.bodySmall.copyWith(color: white),
            cursorColor: accent,
            keyboardAppearance: Brightness.dark,
            decoration: InputDecoration(
              hintText: l.rubricsTemplatesSearchHint,
              prefixIcon: const Padding(
                padding: EdgeInsets.all(14),
                child: FaIcon(
                  FontAwesomeIcons.magnifyingGlass,
                  size: 16,
                  color: primaryLighter,
                ),
              ),
              suffixIcon: query.isEmpty
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
          if (mine.isNotEmpty) ...[
            SectionLabel(l.rubricsYourTemplates),
            for (final template in mine) ...[
              RubricCard(
                cardHintText: l.rubricHint(template),
                cardTitleText: l.titleOf(template),
                trailing: const CardChevron(),
                onTap: () => context.push(Routes.rubric(template.id)),
              ),
              const SizedBox(height: Insets.sm),
            ],
          ],
          for (final subject in subjects) ...[
            SectionLabel(subject),
            for (final template in bySubject[subject]!) ...[
              RubricCard(
                cardHintText: l.rubricHint(
                  template.rubric,
                  lead: template.grades,
                ),
                cardTitleText: template.rubric.title,
                trailing: const CardChevron(),
                onTap: () => context.push(Routes.rubric(template.id)),
              ),
              const SizedBox(height: Insets.sm),
            ],
          ],
          if (mine.isEmpty && subjects.isEmpty)
            EmptyState(
              title: l.rubricsTemplatesNoMatches,
              action: OutlinedButton(
                onPressed: () => setState(_search.clear),
                child: Text(l.rubricsClearFilters),
              ),
            ),
        ],
      ),
    );
  }
}
