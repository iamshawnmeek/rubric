import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/assignments/assignment_logic.dart';
import 'package:rubric/features/assignments/assignment_widgets.dart';
import 'package:rubric/l10n/l10n.dart';

/// "4 objectives · 2 groups".
String rubricSummary(BuildContext context, Rubric rubric) => context.l10n
    .assignmentsRubricSummary(rubric.objectives.length, rubric.groups.length);

/// Lets the teacher pick a ready rubric from the library or the templates.
/// Resolves null when dismissed or when they left to build/fix a rubric.
Future<Rubric?> showRubricPicker(BuildContext context) =>
    showRubricSheet(context: context, child: const _RubricPicker());

enum _Source { library, templates }

class _RubricPicker extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_RubricPicker> createState() => _RubricPickerState();
}

class _RubricPickerState extends ConsumerState<_RubricPicker> {
  _Source _source = _Source.library;
  String _query = '';

  /// Closes the sheet, then opens [location] from the page underneath.
  void _leaveTo(String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    unawaited(router.push(location));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rubrics = ref.watch(
      _source == _Source.library ? rubricsProvider : templatesProvider,
    );

    return RubricSheet(
      title: l10n.assignmentsPickerTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedToggle<_Source>(
            segments: {
              _Source.library: l10n.assignmentsPickerLibrary,
              _Source.templates: l10n.assignmentsPickerTemplates,
            },
            selected: _source,
            onChanged: (s) => setState(() => _source = s),
          ),
          const SizedBox(height: Insets.md),
          RubricFormWell(
            child: RubricTextField(
              key: const Key('assignments.rubricSearch'),
              hintText: l10n.assignmentsPickerSearch,
              onChanged: (q) => setState(() => _query = q),
              style: RubricTextStyles.bodySmall,
              hintStyle: RubricTextStyles.bodySmall,
              textInputAction: TextInputAction.search,
            ),
          ),
          const SizedBox(height: Insets.md),
          AsyncView(
            value: rubrics,
            data: (all) {
              final shown = filterRubrics(all, _query);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (all.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Insets.lg),
                      child: Text(
                        _source == _Source.library
                            ? l10n.assignmentsPickerEmpty
                            : l10n.assignmentsPickerNoTemplates,
                        textAlign: TextAlign.center,
                        style: RubricTextStyles.bodySmall,
                      ),
                    )
                  else if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Insets.lg),
                      child: Text(
                        l10n.assignmentsPickerNoMatches(_query.trim()),
                        textAlign: TextAlign.center,
                        style: RubricTextStyles.bodySmall,
                      ),
                    ),
                  for (final rubric in shown) ...[
                    _PickerRow(
                      rubric: rubric,
                      onPick: () => Navigator.of(context).pop(rubric),
                      onFix: () => _leaveTo(Routes.buildRubric(rubric.id)),
                    ),
                    const SizedBox(height: Insets.sm),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: Insets.xs),
          SheetAction(
            key: const Key('assignments.createRubric'),
            icon: FontAwesomeIcons.plus,
            label: l10n.assignmentsPickerCreate,
            onTap: () => _leaveTo(Routes.buildRubric('new')),
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const new({required this.rubric, required this.onPick, required this.onFix});

  final Rubric rubric;
  final VoidCallback onPick;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = rubric.title.trim().isEmpty
        ? l10n.assignmentsUntitledRubric
        : rubric.title;
    if (canAttach(rubric)) {
      return RubricCard(
        cardHintText: rubricSummary(context, rubric),
        cardTitleText: title,
        onTap: onPick,
      );
    }
    // Not a RubricCard: that merges its semantics, which would hide "Fix".
    final problems = rubric.issues.map((i) => i.label(l10n)).join(', ');
    return Container(
      padding: Insets.card.copyWith(right: Insets.sm),
      decoration: BoxDecoration(color: primary, borderRadius: Corners.card),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardHint(
                  l10n.assignmentsRubricNotReady(problems),
                  color: accent,
                ),
                const SizedBox(height: Insets.xs),
                CardTitle(title, color: primaryLighter),
              ],
            ),
          ),
          TextButton(
            onPressed: onFix,
            child: Text(
              l10n.assignmentsFix,
              semanticsLabel: l10n.assignmentsFixRubric(title),
              style: RubricTextStyles.button.copyWith(color: accent),
            ),
          ),
        ],
      ),
    );
  }
}
