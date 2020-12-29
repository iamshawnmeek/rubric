import 'package:flutter/foundation.dart';

class RubricGroup extends ChangeNotifier {
  /// The group name
  final String title;

  /// A private value used to track the locked state
  bool _isLockedBacking = false;

  /// The percentage this group is worth in the overall grade
  double _weightBacking = 0.0;

  bool get _isLocked => _isLockedBacking;
  double get _weight => _weightBacking;

  set _isLocked(bool value) {
    if (value != _isLocked) {
      _isLocked = value;
      notifyListeners();
    }
  }

  set _weight(double value) {
    if (!_isLocked && value != _weight) {
      _weight = value;
      notifyListeners();
    }
  }

  RubricGroup({
    @required this.title,
    @required double weight,
  }) : _weightBacking = weight;

  void lock() => _isLocked = true;

  void unlock() => _isLocked = false;

  void increaseWeight(double value) => _weight += value;

  void decreaseWeight(double value) => _weight -= value;
}
