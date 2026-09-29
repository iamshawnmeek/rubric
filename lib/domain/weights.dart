/// Whole-number weight arithmetic for rubric groups.
///
/// Replaces the v1 doubly-linked "slider" model. The behaviour it encoded is
/// kept: dragging the boundary between two regions moves weight between the
/// nearest UNLOCKED region on each side, skipping locked ones, and totals always
/// stay at exactly 100.
abstract final class Weights {
  /// [count] weights summing to exactly 100, as even as whole numbers allow
  /// (the remainder goes to the first groups).
  static List<int> equalSplit(int count) {
    if (count <= 0) return const [];
    final base = 100 ~/ count;
    final remainder = 100 - base * count;
    return [for (var i = 0; i < count; i++) base + (i < remainder ? 1 : 0)];
  }

  /// Moves [delta] points across the boundary below index [boundary]
  /// (between region `boundary` and `boundary + 1`). Positive grows the region
  /// above. Returns [weights] unchanged when no unlocked region exists on
  /// either side. Never takes a region below [minWeight].
  static List<int> moveBoundary({
    required List<int> weights,
    required Set<int> locked,
    required int boundary,
    required int delta,
    int minWeight = 1,
  }) {
    if (delta == 0) return weights;
    int? above;
    for (var i = boundary; i >= 0; i--) {
      if (!locked.contains(i)) {
        above = i;
        break;
      }
    }
    int? below;
    for (var i = boundary + 1; i < weights.length; i++) {
      if (!locked.contains(i)) {
        below = i;
        break;
      }
    }
    if (above == null || below == null) return weights;

    final grow = delta > 0 ? above : below;
    final shrink = delta > 0 ? below : above;
    final amount = delta.abs().clamp(0, weights[shrink] - minWeight);
    if (amount <= 0) return weights;

    return List<int>.of(weights)
      ..[grow] += amount
      ..[shrink] -= amount;
  }

  /// Sets region [index] to [value] and absorbs the difference across the
  /// other unlocked regions, proportionally to their current size. [value] is
  /// clamped to what the unlocked regions can give or take.
  static List<int> setWeight({
    required List<int> weights,
    required Set<int> locked,
    required int index,
    required int value,
    int minWeight = 1,
  }) {
    final others = [
      for (var i = 0; i < weights.length; i++)
        if (i != index && !locked.contains(i)) i,
    ];
    if (others.isEmpty) return weights;

    final lockedTotal = [
      for (var i = 0; i < weights.length; i++)
        if (i != index && locked.contains(i)) weights[i],
    ].fold(0, (a, b) => a + b);
    final maxValue = 100 - lockedTotal - others.length * minWeight;
    final target = value.clamp(minWeight, maxValue);
    var remaining = 100 - lockedTotal - target;

    final pool = others.fold(0, (sum, i) => sum + weights[i]);
    final next = List<int>.of(weights)..[index] = target;
    for (var n = 0; n < others.length; n++) {
      final i = others[n];
      final isLast = n == others.length - 1;
      final share = isLast
          ? remaining
          : pool == 0
          ? remaining ~/ (others.length - n)
          : (weights[i] * (100 - lockedTotal - target) / pool).round().clamp(
              minWeight,
              remaining - (others.length - n - 1) * minWeight,
            );
      next[i] = share;
      remaining -= share;
    }
    return next;
  }

  /// Scales arbitrary non-negative weights to whole numbers summing to 100
  /// using largest-remainder rounding.
  static List<int> normalize(List<num> raw) {
    if (raw.isEmpty) return const [];
    final total = raw.fold<num>(0, (a, b) => a + b);
    if (total <= 0) return equalSplit(raw.length);
    final exact = [for (final r in raw) r * 100 / total];
    final floors = [for (final e in exact) e.floor()];
    var remainder = 100 - floors.fold(0, (a, b) => a + b);
    final order = List<int>.generate(raw.length, (i) => i)
      ..sort((a, b) => (exact[b] - floors[b]).compareTo(exact[a] - floors[a]));
    for (final i in order) {
      if (remainder == 0) break;
      floors[i]++;
      remainder--;
    }
    return floors;
  }
}
