import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/domain/weights.dart';

int sum(List<int> w) => w.fold(0, (a, b) => a + b);

void main() {
  group('equalSplit', () {
    test('always sums to 100', () {
      for (var n = 1; n <= 13; n++) {
        final w = Weights.equalSplit(n);
        expect(w, hasLength(n));
        expect(sum(w), 100, reason: 'n=$n');
        expect(
          w.reduce((a, b) => a > b ? a : b) - w.reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(1),
        );
      }
      expect(Weights.equalSplit(0), isEmpty);
    });

    test('remainder goes to the first groups', () {
      expect(Weights.equalSplit(3), [34, 33, 33]);
    });
  });

  group('moveBoundary', () {
    test('moves weight between the neighbours', () {
      expect(
        Weights.moveBoundary(
          weights: [50, 50],
          locked: {},
          boundary: 0,
          delta: 10,
        ),
        [60, 40],
      );
      expect(
        Weights.moveBoundary(
          weights: [50, 50],
          locked: {},
          boundary: 0,
          delta: -10,
        ),
        [40, 60],
      );
    });

    test('skips locked regions to reach the nearest unlocked one', () {
      // Region 1 is locked, so dragging the 0|1 boundary moves weight
      // between regions 0 and 2 — the v1 slider semantics.
      expect(
        Weights.moveBoundary(
          weights: [30, 30, 40],
          locked: {1},
          boundary: 0,
          delta: 10,
        ),
        [40, 30, 30],
      );
    });

    test('does nothing when one side is entirely locked', () {
      final w = [30, 30, 40];
      expect(
        Weights.moveBoundary(weights: w, locked: {0}, boundary: 0, delta: 5),
        same(w),
      );
    });

    test('never takes a region below the minimum', () {
      expect(
        Weights.moveBoundary(
          weights: [90, 10],
          locked: {},
          boundary: 0,
          delta: 50,
        ),
        [99, 1],
      );
    });

    test('preserves the total', () {
      final w = Weights.moveBoundary(
        weights: [25, 25, 25, 25],
        locked: {2},
        boundary: 1,
        delta: -7,
      );
      expect(sum(w), 100);
      expect(w, [25, 18, 25, 32]);
    });
  });

  group('setWeight', () {
    test('absorbs the difference across unlocked regions proportionally', () {
      final w = Weights.setWeight(
        weights: [40, 40, 20],
        locked: {},
        index: 0,
        value: 60,
      );
      expect(w[0], 60);
      expect(sum(w), 100);
      expect(w[1], greaterThan(w[2]));
    });

    test('leaves locked regions alone and clamps to what is available', () {
      final w = Weights.setWeight(
        weights: [20, 50, 30],
        locked: {1},
        index: 0,
        value: 90,
      );
      expect(w, [49, 50, 1]);
    });

    test('is a no-op when every other region is locked', () {
      final w = [20, 50, 30];
      expect(
        Weights.setWeight(weights: w, locked: {1, 2}, index: 0, value: 90),
        same(w),
      );
    });

    test('handles all-zero pools', () {
      final w = Weights.setWeight(
        weights: [100, 0, 0],
        locked: {},
        index: 0,
        value: 40,
      );
      expect(w, [40, 30, 30]);
    });
  });

  group('normalize', () {
    test('largest remainder keeps the sum at exactly 100', () {
      expect(Weights.normalize([1, 1, 1]), [34, 33, 33]);
      expect(sum(Weights.normalize([3, 7, 11, 13])), 100);
      expect(Weights.normalize([0, 0]), [50, 50]);
      expect(Weights.normalize([2, 1, 1]), [50, 25, 25]);
    });
  });
}
