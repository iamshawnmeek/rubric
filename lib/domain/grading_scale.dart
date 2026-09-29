import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A letter grade and the lowest percentage that earns it.
@immutable
class LetterBand {
  const new(this.letter, this.min);

  factory fromJson(Map<String, dynamic> json) =>
      LetterBand(json['letter'] as String, (json['min'] as num).toDouble());

  final String letter;

  /// Inclusive lower bound, 0–100.
  final double min;

  Map<String, dynamic> toJson() => {'letter': letter, 'min': min};

  @override
  bool operator ==(Object other) =>
      other is LetterBand && other.letter == letter && other.min == min;

  @override
  int get hashCode => Object.hash(letter, min);
}

/// Maps a percentage to a letter. Bands are kept sorted highest-first.
@immutable
class GradingScale {
  const new(this.bands);

  factory fromJson(Map<String, dynamic> json) => GradingScale.sorted(
    (json['bands'] as List<dynamic>)
        .map((e) => LetterBand.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  factory sorted(List<LetterBand> bands) =>
      GradingScale(bands.sorted((a, b) => b.min.compareTo(a.min)));

  final List<LetterBand> bands;

  static const standard = GradingScale([
    LetterBand('A', 90),
    LetterBand('B', 80),
    LetterBand('C', 70),
    LetterBand('D', 60),
    LetterBand('F', 0),
  ]);

  static const plusMinus = GradingScale([
    LetterBand('A+', 97),
    LetterBand('A', 93),
    LetterBand('A-', 90),
    LetterBand('B+', 87),
    LetterBand('B', 83),
    LetterBand('B-', 80),
    LetterBand('C+', 77),
    LetterBand('C', 73),
    LetterBand('C-', 70),
    LetterBand('D+', 67),
    LetterBand('D', 63),
    LetterBand('D-', 60),
    LetterBand('F', 0),
  ]);

  static const passFail = GradingScale([
    LetterBand('Pass', 60),
    LetterBand('Fail', 0),
  ]);

  /// The letter for [percent], or the lowest band when below every minimum.
  String letterFor(double percent) {
    for (final band in bands) {
      if (percent >= band.min - 1e-9) return band.letter;
    }
    return bands.isEmpty ? '' : bands.last.letter;
  }

  /// The upper bound shown next to [index] ("80 to 89.9").
  double upperBoundOf(int index) =>
      index == 0 ? 100 : (bands[index - 1].min - 0.1);

  /// Why this scale cannot be used, or null when it is valid.
  String? get problem {
    if (bands.isEmpty) return 'Add at least one grade.';
    if (bands.map((b) => b.letter.trim()).any((l) => l.isEmpty)) {
      return 'Every grade needs a name.';
    }
    if (bands.map((b) => b.letter.trim()).toSet().length != bands.length) {
      return 'Grade names must be unique.';
    }
    if (bands.map((b) => b.min).toSet().length != bands.length) {
      return 'Two grades start at the same percentage.';
    }
    if (bands.any((b) => b.min < 0 || b.min > 100)) {
      return 'Percentages must be between 0 and 100.';
    }
    if (bands.last.min != 0) return 'The lowest grade must start at 0.';
    return null;
  }

  Map<String, dynamic> toJson() => {
    'bands': bands.map((b) => b.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is GradingScale &&
      const ListEquality<LetterBand>().equals(other.bands, bands);

  @override
  int get hashCode => const ListEquality<LetterBand>().hash(bands);
}
