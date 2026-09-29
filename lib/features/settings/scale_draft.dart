import 'package:rubric/domain/grading_scale.dart';

/// One row of the grading-scale editor, exactly as the teacher typed it.
class BandDraft {
  const new(this.letter, this.min);

  final String letter;

  /// The lowest percentage that earns [letter], as raw text.
  final String min;
}

/// Why a drafted scale cannot be saved. Checked in this order, so the teacher
/// sees the first thing to fix.
enum ScaleIssue {
  empty,
  blankName,
  duplicateName,
  badPercent,
  duplicatePercent,
  noZero,
}

/// The built-in scales offered as starting points.
enum ScalePreset {
  standard(GradingScale.standard),
  plusMinus(GradingScale.plusMinus),
  passFail(GradingScale.passFail);

  new(this.scale);

  final GradingScale scale;

  /// The preset [scale] is identical to, or null for a custom scale.
  static ScalePreset? of(GradingScale scale) {
    for (final preset in values) {
      if (preset.scale == scale) return preset;
    }
    return null;
  }
}

/// Parses a typed percentage; null unless it is a number from 0 to 100.
double? parsePercent(String raw) {
  final value = double.tryParse(raw.trim());
  if (value == null || value.isNaN || value < 0 || value > 100) return null;
  return value;
}

/// The first problem with [drafts], or null when they make a usable scale.
ScaleIssue? validateScale(List<BandDraft> drafts) {
  if (drafts.isEmpty) return ScaleIssue.empty;
  final letters = drafts.map((d) => d.letter.trim()).toList();
  if (letters.any((l) => l.isEmpty)) return ScaleIssue.blankName;
  final lowered = letters.map((l) => l.toLowerCase()).toSet();
  if (lowered.length != letters.length) return ScaleIssue.duplicateName;
  final mins = drafts.map((d) => parsePercent(d.min)).toList();
  if (mins.any((m) => m == null)) return ScaleIssue.badPercent;
  if (mins.toSet().length != mins.length) return ScaleIssue.duplicatePercent;
  if (!mins.contains(0)) return ScaleIssue.noZero;
  return null;
}

/// The scale [drafts] describe, highest band first. Call only when
/// [validateScale] returned null.
GradingScale buildScale(List<BandDraft> drafts) {
  assert(validateScale(drafts) == null, 'buildScale on an invalid draft');
  return GradingScale.sorted([
    for (final d in drafts) LetterBand(d.letter.trim(), parsePercent(d.min)!),
  ]);
}

/// The drafts that reproduce [scale] in the editor.
List<BandDraft> draftsOf(GradingScale scale) => [
  for (final band in scale.bands)
    BandDraft(band.letter, formatPercent(band.min)),
];

/// The top of the band starting at [min]: just under the next band up, or 100
/// when nothing is above it. [allMins] may include [min] and unparsed rows.
double upperBoundFor(double min, Iterable<double?> allMins) {
  final above = allMins.whereType<double>().where((m) => m > min);
  if (above.isEmpty) return 100;
  final next = above.reduce((a, b) => a < b ? a : b);
  // One decimal place below the next band, as the v1 table showed (80–89.9).
  return ((next - 0.1) * 10).roundToDouble() / 10;
}

/// "90", "89.9" — whole numbers without a trailing ".0".
String formatPercent(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

/// The next late-penalty value when the teacher taps − or + ([direction] of -1
/// or 1): 5-point steps, snapped to the grid, kept within 0–100.
double stepPenalty(double current, int direction) {
  const step = 5.0;
  final snapped = direction > 0
      ? (current / step).floorToDouble() * step + step
      : (current / step).ceilToDouble() * step - step;
  return snapped.clamp(0, 100).toDouble();
}
