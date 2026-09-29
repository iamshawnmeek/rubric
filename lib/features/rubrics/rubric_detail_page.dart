import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/export/export_actions.dart';
import 'package:rubric/features/rubrics/builtin_templates.dart';
import 'package:rubric/features/rubrics/library_filter.dart';
import 'package:rubric/features/rubrics/rubric_actions.dart';
import 'package:rubric/features/rubrics/rubric_labels.dart';
import 'package:rubric/features/rubrics/rubric_overview.dart';
import 'package:rubric/l10n/l10n.dart';

/// A rubric, read-only, with what can be done with it. [rubricId] may also
/// name a built-in template, which previews it with "Use this template".
class RubricDetailPage extends ConsumerWidget {
  const new({required this.rubricId, super.key});

  final String rubricId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builtin = builtinTemplateById(rubricId);
    if (builtin != null) {
      return _RubricDetail(rubric: builtin.rubric, grades: builtin.grades);
    }

    final l = context.l10n;
    final rubric = ref.watch(rubricProvider(rubricId));
    return switch (rubric) {
      AsyncData(value: final rubric?) => _RubricDetail(rubric: rubric),
      AsyncData() => RubricsContentWidth(
        child: RubricPage(
          title: l.rubricsNotFoundTitle,
          children: [
            EmptyState(
              title: l.rubricsNotFoundMessage,
              action: OutlinedButton(
                onPressed: () => context.go(Routes.rubrics),
                child: Text(l.rubricsBackToLibrary),
              ),
            ),
          ],
        ),
      ),
      _ => RubricsContentWidth(
        child: RubricPage(
          title: '',
          children: [
            AsyncView(value: rubric, data: (_) => const SizedBox.shrink()),
          ],
        ),
      ),
    };
  }
}

class _RubricDetail extends ConsumerWidget {
  const new({required this.rubric, this.grades});

  final Rubric rubric;

  /// Set for built-in templates, which are not stored and cannot be edited.
  final String? grades;

  bool get _builtin => grades != null;

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.rubrics);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final usage = rubric.isTemplate
        ? null
        : ref
              .watch(allAssignmentsProvider)
              .whenData((all) => usageCount(all, rubric.id))
              .value;
    final subtitle = [
      rubric.subject.trim(),
      ?grades,
    ].where((s) => s.isNotEmpty).join(' · ');

    return RubricsContentWidth(
      child: RubricPage(
        title: l.titleOf(rubric),
        subtitle: subtitle.isEmpty ? null : subtitle,
        actions: [
          if (_builtin)
            HeaderAction(
              icon: FontAwesomeIcons.print,
              label: l.rubricsActionPrint,
              onTap: () => exportRubricPdf(context, rubric),
            )
          else ...[
            HeaderAction(
              icon: FontAwesomeIcons.pen,
              label: l.rubricsActionEdit,
              onTap: () => RubricActions.edit(context, rubric),
            ),
            RubricMenuButton(
              rubric: rubric,
              showEdit: false,
              showPrint: true,
              onDeleted: () => _leave(context),
            ),
          ],
        ],
        bottomCta: rubric.isTemplate
            ? AccentButton(
                label: l.rubricsUseTemplate,
                widthFactor: .2,
                onTap: () => RubricActions.useTemplate(context, ref, rubric),
              )
            : AccentButton(
                label: l.rubricsUseInAssignment,
                widthFactor: .2,
                enabled: rubric.isReady && !rubric.archived,
                onTap: () {
                  showRubricSnack(context, l.rubricsUseInAssignmentHint);
                  context.go(Routes.classes);
                },
              ),
        children: [RubricOverview(rubric: rubric, usage: usage)],
      ),
    );
  }
}
