import 'package:flutter/foundation.dart';

import 'package:rubric/domain/weight/rubric_group.dart';

enum Direction { up, down, undetermined }

class Slider {
  final RubricGroup regionBefore;
  final RubricGroup regionAfter;
  ScrollPosition _current;
  ScrollPosition _previous;

  /// The current scroll position
  double get scrollPosition => _current.value;

  Slider({
    @required this.regionBefore,
    @required this.regionAfter,
    @required ScrollPosition initial,
  }) : _current = initial;

  ScrollDelta getScrollDelta(ScrollPosition scrollPosition) =>
      ScrollDelta.fromPositions(previous: _current, next: scrollPosition);

  void handleAdjustment(ScrollDelta scrollDelta) {
    _setScrollPosition(scrollDelta);
    _setGroupValues(scrollDelta);
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

  /// Adjust the previous and next group values based on the location offset
  void _setGroupValues(ScrollDelta delta) {
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
  final double value;
  const ScrollPosition(this.value);
}

class ScrollDelta {
  final Direction direction;
  final double value;

  const ScrollDelta({
    @required this.direction,
    @required this.value,
  });

  static ScrollDelta fromPositions({
    @required ScrollPosition previous,
    @required ScrollPosition next,
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
