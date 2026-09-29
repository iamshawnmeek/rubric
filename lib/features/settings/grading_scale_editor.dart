import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/features/settings/scale_draft.dart';
import 'package:rubric/l10n/l10n.dart';

/// Opens the band-table editor on [initial]. Resolves to the saved scale, or
/// null when the teacher backs out.
Future<GradingScale?> showGradingScaleEditor(
  BuildContext context,
  GradingScale initial,
) => showRubricSheet<GradingScale>(
  context: context,
  child: GradingScaleEditor(initial: initial),
);

String presetName(AppLocalizations l, ScalePreset preset) => switch (preset) {
  ScalePreset.standard => l.settingsScalePresetStandard,
  ScalePreset.plusMinus => l.settingsScalePresetPlusMinus,
  ScalePreset.passFail => l.settingsScalePresetPassFail,
};

String scaleIssueText(AppLocalizations l, ScaleIssue issue) => switch (issue) {
  ScaleIssue.empty => l.settingsScaleIssueEmpty,
  ScaleIssue.blankName => l.settingsScaleIssueBlankName,
  ScaleIssue.duplicateName => l.settingsScaleIssueDuplicateName,
  ScaleIssue.badPercent => l.settingsScaleIssueBadPercent,
  ScaleIssue.duplicatePercent => l.settingsScaleIssueDuplicatePercent,
  ScaleIssue.noZero => l.settingsScaleIssueNoZero,
};

/// The v1 grading-scale table ("A  [90] to 100"), made editable: presets to
/// start from, rows to rename, re-threshold, add and remove.
class GradingScaleEditor extends StatefulWidget {
  const new({required this.initial, super.key});

  final GradingScale initial;

  @override
  State<GradingScaleEditor> createState() => _GradingScaleEditorState();
}

class _Row {
  new(BandDraft draft)
    : letter = TextEditingController(text: draft.letter),
      min = TextEditingController(text: draft.min);

  final key = UniqueKey();
  final TextEditingController letter;
  final TextEditingController min;

  BandDraft get draft => BandDraft(letter.text, min.text);

  void dispose() {
    letter.dispose();
    min.dispose();
  }
}

class _GradingScaleEditorState extends State<GradingScaleEditor> {
  late List<_Row> _rows = _rowsFor(widget.initial);

  List<_Row> _rowsFor(GradingScale scale) => [
    for (final draft in draftsOf(scale)) _Row(draft),
  ];

  List<BandDraft> get _drafts => [for (final r in _rows) r.draft];

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _applyPreset(ScalePreset preset) {
    final old = _rows;
    setState(() => _rows = _rowsFor(preset.scale));
    // Dispose after the frame that stops using them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final row in old) {
        row.dispose();
      }
    });
  }

  void _add() {
    setState(() => _rows = [..._rows, _Row(const BandDraft('', ''))]);
  }

  void _remove(_Row row) {
    setState(() => _rows = [..._rows]..remove(row));
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final drafts = _drafts;
    final issue = validateScale(drafts);
    final current = issue == null ? buildScale(drafts) : null;
    final selectedPreset = current == null ? null : ScalePreset.of(current);
    final mins = [for (final d in drafts) parsePercent(d.min)];

    return RubricSheet(
      title: l.settingsScaleEditorTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.settingsScalePresetsLabel.toUpperCase(),
            style: RubricTextStyles.sectionLabel,
          ),
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: Insets.xs,
            runSpacing: Insets.xs,
            children: [
              for (final preset in ScalePreset.values)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Sizes.minTap),
                  child: Center(
                    widthFactor: 1,
                    child: RubricChip(
                      label: presetName(l, preset),
                      selected: preset == selectedPreset,
                      onTap: () => _applyPreset(preset),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          for (final (i, row) in _rows.indexed) ...[
            if (i > 0) const SizedBox(height: Insets.sm),
            _BandRow(
              key: row.key,
              index: i + 1,
              row: row,
              upper: mins[i] == null
                  ? '–'
                  : formatPercent(upperBoundFor(mins[i]!, mins)),
              onChanged: () => setState(() {}),
              onRemove: _rows.length > 1 ? () => _remove(row) : null,
            ),
          ],
          const SizedBox(height: Insets.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _add,
              icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
              label: Text(l.settingsScaleAddGrade),
            ),
          ),
          const SizedBox(height: Insets.sm),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            child: issue == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: Insets.sm),
                    child: Semantics(
                      liveRegion: true,
                      child: Row(
                        children: [
                          const FaIcon(
                            FontAwesomeIcons.circleExclamation,
                            color: accent,
                            size: 16,
                          ),
                          const SizedBox(width: Insets.xs),
                          Expanded(
                            child: Text(
                              scaleIssueText(l, issue),
                              style: RubricTextStyles.bodySmall.copyWith(
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          FilledButton(
            onPressed: current == null
                ? null
                : () => Navigator.of(context).pop(current),
            child: Text(l.settingsScaleSave),
          ),
        ],
      ),
    );
  }
}

class _BandRow extends StatelessWidget {
  const new({
    required this.index,
    required this.row,
    required this.upper,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _Row row;
  final String upper;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final style = RubricTextStyles.gradingScaleInput.copyWith(color: white);
    InputDecoration decoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: RubricTextStyles.caption,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Semantics(
            label: l.settingsScaleGradeLabel(index),
            child: TextField(
              controller: row.letter,
              onChanged: (_) => onChanged(),
              style: style,
              cursorColor: accent,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              keyboardAppearance: Brightness.dark,
              inputFormatters: [LengthLimitingTextInputFormatter(8)],
              decoration: decoration(l.settingsScaleGradeHint),
            ),
          ),
        ),
        const SizedBox(width: Insets.xs),
        Expanded(
          flex: 5,
          child: Semantics(
            label: l.settingsScaleFromLabel(index),
            child: TextField(
              controller: row.min,
              onChanged: (_) => onChanged(),
              style: style,
              cursorColor: accent,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.next,
              keyboardAppearance: Brightness.dark,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: decoration(l.settingsScaleFromHint),
            ),
          ),
        ),
        const SizedBox(width: Insets.xs),
        Expanded(
          flex: 4,
          child: Text(
            l.settingsScaleTo(upper),
            style: RubricTextStyles.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
          ),
        ),
        SizedBox.square(
          dimension: Sizes.minTap,
          child: onRemove == null
              ? null
              : IconButton(
                  tooltip: l.settingsScaleRemoveGrade(index),
                  onPressed: onRemove,
                  icon: const FaIcon(
                    FontAwesomeIcons.xmark,
                    color: primaryLightest,
                    size: 18,
                  ),
                ),
        ),
      ],
    );
  }
}
