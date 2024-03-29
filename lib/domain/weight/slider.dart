import 'package:rubric/domain/weight/rubric_region.dart';

enum Direction { up, down, undetermined }

class Slider {
  Slider({
    required this.regionBefore,
    required this.regionAfter,
    required ScrollPosition initial,
  }) : _current = initial;

  double get scrollPosition => _current.value;
  // The current scroll position

  final RubricRegion regionBefore;
  final RubricRegion regionAfter;
  ScrollPosition _current;
  ScrollPosition? _previous;

  ScrollDelta getScrollDelta(ScrollPosition scrollPosition) =>
      ScrollDelta.fromPositions(previous: _current, next: scrollPosition);

  void handleAdjustment(ScrollDelta scrollDelta) {
    _setScrollPosition(scrollDelta);
    _setRegionValues(scrollDelta);
  }

  /// Cache the current location as the previous location and adjust the current
  /// location with the new offset
  void _setScrollPosition(ScrollDelta delta) {
    final isInvalidPosition = delta.value > _current.value;
    if (isInvalidPosition) return;

    final nextPosition = delta.direction == Direction.up
        ? _current.value - delta.value
        : _current.value + delta.value;

    if (_previous != _current) {
      _previous = _current;
      _current = ScrollPosition(nextPosition);
    }
  }

  /// Adjust the previous and next region values based on the location offset
  void _setRegionValues(ScrollDelta delta) {
    switch (delta.direction) {
      case Direction.up:
        if (delta.value <= regionBefore.weight) {
          regionBefore.decreaseWeight(delta.value);
          regionAfter.increaseWeight(delta.value);
        }
        break;
      case Direction.down:
        if (delta.value <= regionAfter.weight) {
          regionBefore.increaseWeight(delta.value);
          regionAfter.decreaseWeight(delta.value);
        }
        break;
      case Direction.undetermined:
        break;
    }
  }
}

class ScrollPosition {
  const ScrollPosition(this.value);

  final double value;

  static ScrollPosition fromGlobal({
    required double updatedY,
    required double globalHeight,
    required double currentScrollPosition,
  }) {
    final currentY = (currentScrollPosition / 100) * globalHeight;
    final percentChange = (updatedY - currentY).abs();

    return ScrollPosition(percentChange);
  }
}

class ScrollDelta {
  const ScrollDelta({
    required this.direction,
    required this.value,
  });

  final Direction direction;
  final double value;

  static ScrollDelta fromPositions({
    required ScrollPosition previous,
    required ScrollPosition next,
  }) {
    final delta = previous.value - next.value;

    final direction = delta.toDirection();

    return ScrollDelta(direction: direction, value: delta.abs());
  }
}

extension DirectionExtension on double {
  Direction toDirection() {
    Direction getDirection() => isNegative ? Direction.down : Direction.up;
    final isUndetermined = isNaN || this == 0.0;

    return isUndetermined ? Direction.undetermined : getDirection();
  }
}
