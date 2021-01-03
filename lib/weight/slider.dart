import 'package:flutter/foundation.dart';
import 'package:rubric/weight/rubric_group.dart';

enum Direction { up, down, undetermined }

class Slider {
  final RubricGroup regionBefore;
  final RubricGroup regionAfter;
  ScrollPosition _current;
  ScrollPosition _previous;

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
    final scrollPosition = delta.direction == Direction.up
        ? _current.value - delta.value
        : _current.value + delta.value;

    if (_previous != _current) {
      _previous = _current;
      _current = ScrollPosition(scrollPosition);
    }
  }

  /// Adjust the previous and next group values based on the location offset
  void _setGroupValues(ScrollDelta delta) {
    switch (delta.direction) {
      case Direction.up:
        regionBefore.decreaseWeight(delta.value);
        regionAfter.increaseWeight(delta.value);
        break;
      case Direction.down:
        regionBefore.increaseWeight(delta.value);
        regionAfter.decreaseWeight(delta.value);
        break;
      case Direction.undetermined:
        break;
    }
  }
}

class ScrollPosition {
  final double value;
  const ScrollPosition(this.value);

  operator <(ScrollPosition sp) => value < sp.value;
  operator >(ScrollPosition sp) => value > sp.value;
  operator -(ScrollPosition sp) {
    final delta = value - sp.value;

    return ScrollDelta(
      direction: delta.toDirection(),
      value: delta.abs(),
    );
  }

  operator *(ScrollPosition sp) => value * sp.value;
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

  operator <(ScrollDelta sd) => value < sd.value;
  operator >(ScrollDelta sd) => value > sd.value;
  operator -(ScrollDelta sd) => value - sd.value;
  operator *(ScrollDelta sd) => value * sd.value;
}

extension DirectionExtension on double {
  Direction toDirection() {
    Direction getDirection() => isNegative ? Direction.down : Direction.up;
    final isUndetermined = isNaN || this == 0.0;

    return isUndetermined ? Direction.undetermined : getDirection();
  }
}
