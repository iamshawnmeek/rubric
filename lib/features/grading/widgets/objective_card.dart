import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/grading/grading_controller.dart';
import 'package:rubric/features/grading/grading_logic.dart';
import 'package:rubric/features/grading/widgets/grading_actions.dart';
import 'package:rubric/features/grading/widgets/synced_text_field.dart';
import 'package:rubric/l10n/l10n.dart';

/// One objective on the grading screen: a primaryCard with the objective as
/// CardHint/CardTitle, the scoring control for the rubric's mode, and an
/// expandable per-objective comment.
class ObjectiveCard extends ConsumerWidget {
  const new({
    required this.args,
    required this.rubric,
    required this.objective,
    required this.number,
    required this.evaluation,
    super.key,
  });

  final GradingArgs args;
  final Rubric rubric;
  final Objective objective;

  /// 1-based position across the whole rubric.
  final int number;
  final Evaluation evaluation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final decimals = ref.watch(settingsProvider.select((s) => s.decimals));
    final score = evaluation.scores[objective.id];
    final percent = Scoring.objectivePercent(rubric, score);
    final hint = percent == null
        ? l10n.gradingObjectiveHint(number)
        : l10n.gradingObjectiveScored(
            number,
            formatPercent(percent, decimals: decimals),
          );

    return Container(
      decoration: BoxDecoration(color: primaryCard, borderRadius: Corners.card),
      padding: Insets.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardHint(hint),
                const SizedBox(height: Insets.xs),
                CardTitle(objective.title),
              ],
            ),
          ),
          if (objective.description.trim().isNotEmpty) ...[
            const SizedBox(height: Insets.xs),
            Text(objective.description, style: RubricTextStyles.bodySmall),
          ],
          const SizedBox(height: Insets.md),
          if (rubric.mode == GradingMode.simple)
            _PercentInput(
              args: args,
              objective: objective,
              score: score is PercentScore ? score.value : null,
            )
          else
            _LevelPicker(
              args: args,
              rubric: rubric,
              objective: objective,
              selectedLevelId: score is LevelScore ? score.levelId : null,
            ),
          _ObjectiveComment(
            args: args,
            objectiveId: objective.id,
            comment: evaluation.objectiveComments[objective.id] ?? '',
          ),
        ],
      ),
    );
  }
}

class _PercentInput extends ConsumerWidget {
  const new({required this.args, required this.objective, this.score});

  final GradingArgs args;
  final Objective objective;
  final double? score;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    void set(double? v, {String? coalesce, bool haptic = true}) =>
        ref.gradeEdit(
          args,
          (rubric, e) => GradingLogic.setScore(
            rubric,
            e,
            objective.id,
            v == null ? null : PercentScore(v),
          ),
          coalesce: coalesce,
          haptic: haptic,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Insets.xs,
          runSpacing: Insets.xs,
          children: [
            for (final pick in GradingLogic.quickPicks)
              _MinTap(
                onTap: () => set(score == pick ? null : pick),
                child: RubricChip(
                  label: formatPercent(pick, decimals: 0),
                  selected: score == pick,
                  onTap: () => set(score == pick ? null : pick),
                ),
              ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: l10n.gradingSliderLabel(objective.title),
                child: Slider(
                  value: score ?? 0,
                  max: 100,
                  divisions: 100,
                  label: formatPercent(score ?? 0, decimals: 0),
                  inactiveColor: primaryDark,
                  activeColor: score == null ? inactive : accent,
                  onChanged: (v) => set(
                    v.roundToDouble(),
                    coalesce: 'slider:${objective.id}',
                    haptic: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Insets.xs),
            Container(
              width: 84,
              constraints: const BoxConstraints(minHeight: Sizes.minTap),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: Corners.card,
              ),
              child: SyncedTextField(
                value: score == null ? '' : _trim(score!),
                hintText: '—',
                semanticLabel: '${objective.title} ${l10n.gradingPercentField}',
                style: RubricTextStyles.listTitle,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                ],
                onChanged: (text) {
                  final v = text.trim().isEmpty
                      ? null
                      : GradingLogic.parsePercent(text);
                  if (text.trim().isNotEmpty && v == null) return;
                  set(v, coalesce: 'typed:${objective.id}', haptic: false);
                },
              ),
            ),
            const SizedBox(width: 2),
            const Text('%', style: RubricTextStyles.cardHint),
          ],
        ),
      ],
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

class _LevelPicker extends ConsumerWidget {
  const new({
    required this.args,
    required this.rubric,
    required this.objective,
    this.selectedLevelId,
  });

  final GradingArgs args;
  final Rubric rubric;
  final Objective objective;
  final String? selectedLevelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final level in rubric.levels) ...[
          _LevelTile(
            label: level.label,
            points: l10n.gradingLevelPoints(_points(level.points)),
            descriptor: objective.descriptors[level.id] ?? '',
            selected: level.id == selectedLevelId,
            semanticLabel: l10n.gradingLevelSemantics(
              level.label,
              _points(level.points),
              objective.descriptors[level.id] ?? '',
            ),
            onTap: () => ref.gradeEdit(
              args,
              (rubric, e) =>
                  GradingLogic.toggleLevel(rubric, e, objective.id, level.id),
              haptic: true,
            ),
          ),
          const SizedBox(height: Insets.xs),
        ],
      ],
    );
  }

  static String _points(double p) =>
      p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toString();
}

class _LevelTile extends StatelessWidget {
  const new({
    required this.label,
    required this.points,
    required this.descriptor,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final String points;
  final String descriptor;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? secondary : white;
    final sub = selected ? primaryDark : primaryLighter;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: selected ? accent : primaryDark,
        borderRadius: Corners.card,
        child: InkWell(
          borderRadius: Corners.card,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: Sizes.minTap),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // A check as well as the fill, so selection never rests on
                    // colour alone.
                    if (selected) ...[
                      FaIcon(FontAwesomeIcons.check, size: 16, color: fg),
                      const SizedBox(width: Insets.xs),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        style: RubricTextStyles.listTitle.copyWith(color: fg),
                      ),
                    ),
                    Text(
                      points,
                      style: RubricTextStyles.caption.copyWith(color: sub),
                    ),
                  ],
                ),
                if (descriptor.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    descriptor,
                    style: RubricTextStyles.bodySmall.copyWith(color: sub),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ObjectiveComment extends ConsumerStatefulWidget {
  const new({
    required this.args,
    required this.objectiveId,
    required this.comment,
  });

  final GradingArgs args;
  final String objectiveId;
  final String comment;

  @override
  ConsumerState<_ObjectiveComment> createState() => _ObjectiveCommentState();
}

class _ObjectiveCommentState extends ConsumerState<_ObjectiveComment> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final expanded = _open || widget.comment.trim().isNotEmpty;
    if (!expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _open = true),
          icon: const FaIcon(FontAwesomeIcons.commentDots, size: 16),
          label: Text(l10n.gradingAddObjectiveComment),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: Insets.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: primary, borderRadius: Corners.card),
        child: SyncedTextField(
          value: widget.comment,
          hintText: l10n.gradingObjectiveCommentHint,
          semanticLabel: l10n.gradingEditObjectiveComment,
          style: RubricTextStyles.bodySmall,
          maxLines: null,
          minLines: 2,
          onChanged: (text) => ref.gradeEdit(
            widget.args,
            (_, e) =>
                GradingLogic.setObjectiveComment(e, widget.objectiveId, text),
            coalesce: 'objectiveComment:${widget.objectiveId}',
          ),
        ),
      ),
    );
  }
}

/// Grows a small control's hit area to the 48pt minimum tap target.
class _MinTap extends StatelessWidget {
  const new({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    excludeFromSemantics: true,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Sizes.minTap),
      child: Center(widthFactor: 1, child: child),
    ),
  );
}
