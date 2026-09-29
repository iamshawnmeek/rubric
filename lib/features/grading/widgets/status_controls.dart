import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/scoring.dart';
import 'package:rubric/domain/stats.dart';
import 'package:rubric/features/grading/grading_controller.dart';
import 'package:rubric/features/grading/grading_logic.dart';
import 'package:rubric/features/grading/widgets/grading_actions.dart';
import 'package:rubric/features/grading/widgets/synced_text_field.dart';
import 'package:rubric/l10n/l10n.dart';

/// Missing / Excused / Late / Override for the current student.
class StatusControls extends ConsumerWidget {
  const new({required this.args, required this.session, super.key});

  final GradingArgs args;
  final GradingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final e = session.evaluation;
    final decimals = ref.watch(settingsProvider.select((s) => s.decimals));
    final missing = e.status == EvaluationStatus.missing;
    final excused = e.status == EvaluationStatus.excused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Insets.xs,
          runSpacing: Insets.xs,
          children: [
            _Toggle(
              label: l10n.gradingMissing,
              icon: Icons.assignment_late_outlined,
              selected: missing,
              onTap: () => ref.gradeEdit(
                args,
                (rubric, e) =>
                    GradingLogic.setMissing(rubric, e, missing: !missing),
                haptic: true,
              ),
            ),
            _Toggle(
              label: l10n.gradingExcused,
              icon: Icons.person_off_outlined,
              selected: excused,
              onTap: () => ref.gradeEdit(
                args,
                (rubric, e) =>
                    GradingLogic.setExcused(rubric, e, excused: !excused),
                haptic: true,
              ),
            ),
            _Toggle(
              label: l10n.gradingLate,
              icon: Icons.schedule,
              selected: e.late,
              onTap: () => ref.gradeEdit(
                args,
                (_, e) => GradingLogic.setLate(
                  e,
                  late: !e.late,
                  defaultPenalty: ref.read(settingsProvider).latePenaltyPercent,
                ),
                haptic: true,
              ),
            ),
            _Toggle(
              label: e.overridePercent == null
                  ? l10n.gradingOverride
                  : l10n.gradingOverrideActive(
                      formatPercent(e.overridePercent, decimals: decimals),
                    ),
              icon: Icons.edit_outlined,
              selected: e.overridePercent != null,
              onTap: () => showOverrideSheet(context, ref, args, session),
            ),
          ],
        ),
        if (e.late) ...[
          const SizedBox(height: Insets.sm),
          _PenaltyField(args: args, penalty: e.penaltyPercent),
        ],
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const new({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      excludeFromSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.minTap),
        child: Center(
          widthFactor: 1,
          child: RubricChip(
            label: label,
            // The icon swaps to a check when on, so state isn't colour-only.
            icon: selected ? Icons.check : icon,
            selected: selected,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

class _PenaltyField extends ConsumerWidget {
  const new({required this.args, required this.penalty});

  final GradingArgs args;
  final double penalty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      constraints: const BoxConstraints(minHeight: Sizes.minTap),
      decoration: BoxDecoration(color: primaryDark, borderRadius: Corners.card),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.gradingPenaltyLabel,
              style: RubricTextStyles.bodySmall,
            ),
          ),
          const Text('−', style: RubricTextStyles.listTitle),
          SizedBox(
            width: 56,
            child: SyncedTextField(
              value: _trim(penalty),
              hintText: '0',
              semanticLabel: l10n.gradingPenaltyHint,
              style: RubricTextStyles.listTitle,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
              ],
              onChanged: (text) {
                final v = text.trim().isEmpty
                    ? 0.0
                    : GradingLogic.parsePercent(text);
                if (v == null) return;
                ref.gradeEdit(
                  args,
                  (_, e) => GradingLogic.setPenalty(e, v),
                  coalesce: 'penalty',
                );
              },
            ),
          ),
          const Text('%', style: RubricTextStyles.cardHint),
        ],
      ),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// Opens the override sheet for the current student.
Future<void> showOverrideSheet(
  BuildContext context,
  WidgetRef ref,
  GradingArgs args,
  GradingSession session,
) {
  return showRubricSheet<void>(
    context: context,
    child: _OverrideSheet(args: args, session: session),
  );
}

class _OverrideSheet extends ConsumerStatefulWidget {
  const new({required this.args, required this.session});

  final GradingArgs args;
  final GradingSession session;

  @override
  ConsumerState<_OverrideSheet> createState() => _OverrideSheetState();
}

class _OverrideSheetState extends ConsumerState<_OverrideSheet> {
  late final _percent = TextEditingController(
    text: widget.session.evaluation.overridePercent == null
        ? ''
        : formatPercent(widget.session.evaluation.overridePercent)
              .replaceAll('%', ''),
  );
  late final _reason = TextEditingController(
    text: widget.session.evaluation.overrideReason,
  );
  bool _invalid = false;

  @override
  void dispose() {
    _percent.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _apply() {
    final v = double.tryParse(_percent.text.replaceAll('%', '').trim());
    if (v == null || v < 0 || v > 100) {
      setState(() => _invalid = true);
      return;
    }
    ref.gradeEdit(
      widget.args,
      (_, e) => GradingLogic.setOverride(e, v, reason: _reason.text),
      haptic: true,
    );
    Navigator.of(context).pop();
  }

  void _clear() {
    ref.gradeEdit(
      widget.args,
      (_, e) => GradingLogic.setOverride(e, null),
      haptic: true,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = widget.session;
    final raw = Scoring.score(
      session.rubric,
      session.evaluation.copyWith(clearOverride: true),
    ).percent;
    final hasOverride = session.evaluation.overridePercent != null;

    return RubricSheet(
      title: l10n.gradingOverrideTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.gradingOverrideComputed(formatPercent(raw)),
            style: RubricTextStyles.bodySmall,
          ),
          const SizedBox(height: Insets.md),
          RubricFormWell(
            child: RubricTextField(
              controller: _percent,
              hintText: l10n.gradingOverridePercent,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
              ],
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
            ),
          ),
          if (_invalid) ...[
            const SizedBox(height: Insets.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.gradingOverrideInvalid,
                style: RubricTextStyles.caption.copyWith(color: accent),
              ),
            ),
          ],
          const SizedBox(height: Insets.sm),
          RubricFormWell(
            child: RubricTextField(
              controller: _reason,
              hintText: l10n.gradingOverrideReason,
              maxLines: 3,
              minLines: 1,
              style: RubricTextStyles.bodySmall,
              hintStyle: RubricTextStyles.bodySmall,
              onSubmitted: (_) => _apply(),
            ),
          ),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              if (hasOverride)
                TextButton(
                  onPressed: _clear,
                  child: Text(l10n.gradingOverrideClear),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _apply,
                child: Text(l10n.gradingOverrideApply),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
