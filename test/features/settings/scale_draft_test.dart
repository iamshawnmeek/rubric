import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/features/settings/scale_draft.dart';

void main() {
  group('validateScale', () {
    ScaleIssue? v(List<(String, String)> rows) =>
        validateScale([for (final (l, m) in rows) BandDraft(l, m)]);

    test('accepts a valid scale in any row order', () {
      expect(v([('F', '0'), ('A', '90'), ('B', '80')]), isNull);
    });

    test('names each problem', () {
      expect(v([]), ScaleIssue.empty);
      expect(v([('A', '90'), (' ', '0')]), ScaleIssue.blankName);
      expect(v([('A', '90'), ('a', '0')]), ScaleIssue.duplicateName);
      expect(v([('A', '101'), ('F', '0')]), ScaleIssue.badPercent);
      expect(v([('A', ''), ('F', '0')]), ScaleIssue.badPercent);
      expect(v([('A', '9.9.9'), ('F', '0')]), ScaleIssue.badPercent);
      expect(
        v([('A', '50'), ('B', '50.0'), ('F', '0')]),
        ScaleIssue.duplicatePercent,
      );
      expect(v([('A', '90'), ('F', '10')]), ScaleIssue.noZero);
    });

    test('every preset is valid and round-trips through the editor', () {
      for (final preset in ScalePreset.values) {
        final drafts = draftsOf(preset.scale);
        expect(validateScale(drafts), isNull, reason: preset.name);
        expect(buildScale(drafts), preset.scale, reason: preset.name);
      }
    });
  });

  test('buildScale trims names and sorts highest first', () {
    final scale = buildScale(const [
      BandDraft(' F ', '0'),
      BandDraft('A', '90'),
      BandDraft('B', '80.5'),
    ]);
    expect(
      scale,
      const GradingScale([
        LetterBand('A', 90),
        LetterBand('B', 80.5),
        LetterBand('F', 0),
      ]),
    );
  });

  test('ScalePreset.of recognises presets and nothing else', () {
    expect(ScalePreset.of(GradingScale.standard), ScalePreset.standard);
    expect(ScalePreset.of(GradingScale.passFail), ScalePreset.passFail);
    expect(
      ScalePreset.of(
        const GradingScale([LetterBand('A', 50), LetterBand('F', 0)]),
      ),
      isNull,
    );
  });

  test('upperBoundFor sits just under the next band up', () {
    const mins = [90.0, 80.0, null, 0.0];
    expect(upperBoundFor(90, mins), 100);
    expect(upperBoundFor(80, mins), 89.9);
    expect(upperBoundFor(0, mins), 79.9);
    expect(upperBoundFor(77, [77, 80.5]), 80.4);
  });

  test('formatPercent drops a trailing .0', () {
    expect(formatPercent(90), '90');
    expect(formatPercent(89.9), '89.9');
  });

  test('stepPenalty moves in 5s, snaps to the grid and clamps', () {
    expect(stepPenalty(10, 1), 15);
    expect(stepPenalty(10, -1), 5);
    expect(stepPenalty(7, 1), 10);
    expect(stepPenalty(7, -1), 5);
    expect(stepPenalty(0, -1), 0);
    expect(stepPenalty(100, 1), 100);
    expect(stepPenalty(98, 1), 100);
  });
}
