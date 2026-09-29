import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:rubric/domain/evaluation.dart';

import '../helpers/fixtures.dart';

void main() {
  group('Evaluation.overrideReason', () {
    test('round-trips through json', () {
      final e = eval(const {'o1': PercentScore(80)}).copyWith(
        overridePercent: 95,
        overrideReason: 'Extra credit',
        updatedAt: t0,
      );
      final back = Evaluation.fromJson(e.toJson());
      expect(back.overrideReason, 'Extra credit');
      expect(back, e);
    });

    test('defaults to empty when absent from older documents', () {
      final json = eval(const {}).copyWith(overridePercent: 90).toJson()
        ..remove('overrideReason');
      expect(Evaluation.fromJson(json).overrideReason, '');
    });

    test('is part of equality', () {
      final a = eval(const {}).copyWith(updatedAt: t0, overrideReason: 'x');
      final b = a.copyWith(updatedAt: t0, overrideReason: 'y');
      expect(a == b, isFalse);
    });

    test('clearOverride clears the reason with the percent', () {
      final e = eval(const {})
          .copyWith(overridePercent: 90, overrideReason: 'Retake');
      final cleared = e.copyWith(clearOverride: true);
      expect(cleared.overridePercent, isNull);
      expect(cleared.overrideReason, '');
    });
  });
}
