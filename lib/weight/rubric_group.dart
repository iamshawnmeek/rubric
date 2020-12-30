import 'package:flutter/foundation.dart';

class RubricGroup extends ChangeNotifier {
  /// The group name
  final String title;

  /// A private value used to track the locked state
  bool _isLockedBacking = false;

  /// The percentage this group is worth in the overall grade
  double _weightBacking = 0.0;

  bool get isLocked => _isLockedBacking;
  double get weight => _weightBacking;

  set isLocked(bool value) {
    if (value != isLocked) {
      _isLockedBacking = value;
      notifyListeners();
    }
  }

  set weight(double value) {
    if (!isLocked && value != weight) {
      _weightBacking = value;
      notifyListeners();
    }
  }

  RubricGroup({
    @required this.title,
    @required double weight,
  }) : _weightBacking = weight;

  void lock() => isLocked = true;

  void unlock() => isLocked = false;

  void increaseWeight(double value) => weight += value;

  void decreaseWeight(double value) => weight -= value;
}
