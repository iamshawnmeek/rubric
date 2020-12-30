import 'package:flutter/foundation.dart';
import 'package:rubric/weight/rubric_group.dart';

enum Direction { up, down, undetermined }

class Slider {
  final RubricGroup previous;
  final RubricGroup next;
  double _currentLocation;
  double _previousLocation;
  Direction _direction = Direction.undetermined;

  Slider({
    @required this.previous,
    @required this.next,
    @required double initialLocation,
  }) : _currentLocation = initialLocation;

  void handleAdjustment(double location) {
    _setLocation(location);
    _setDirection();
    _setGroupValues();
  }

  /// Cache the current location as the previous location and update the current
  /// location to match what's passed in
  void _setLocation(double location) {
    if (_previousLocation != _currentLocation) {
      _previousLocation = _currentLocation;
      _currentLocation = location;
    }
  }

  /// Use the previous and current location to determine the direction the
  /// slider is moving
  void _setDirection() {
    final isMovingUp = _previousLocation > _currentLocation;
    final isMovingDown = _previousLocation < _currentLocation;

    if (isMovingUp) {
      _direction = Direction.up;
    } else if (isMovingDown) {
      _direction = Direction.down;
    } else {
      _direction = Direction.undetermined;
    }
  }

  /// Adjust the previous and next group values based on the location offset
  void _setGroupValues() {
    final adjustment = _getOffset();

    switch (_direction) {
      case Direction.up:
        previous.decreaseWeight(adjustment);
        next.increaseWeight(adjustment);
        break;
      case Direction.down:
        previous.increaseWeight(adjustment);
        next.decreaseWeight(adjustment);
        break;
      case Direction.undetermined:
        break;
    }
  }

  double _getOffset() => (_previousLocation - _currentLocation).abs();
}
