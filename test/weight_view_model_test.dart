import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/weight/rubric_group.dart';
import 'package:rubric/weight/slider.dart';
import 'package:rubric/weight/weight_view_model.dart';

void main() {
  test('should create a WeightController', () {
    final groups = <String>['test1', 'test2', 'test3'];
    final model = WeightViewModel(groupNames: groups);

    expect(model.weightController, isNotNull);
  });

  test('controller should contain sliders', () {
    final groups = <String>['test1', 'test2', 'test3', 'test4'];
    final model = WeightViewModel(groupNames: groups);

    final sliderCount = groups.length - 1;

    expect(model.weightController.length, sliderCount);
  });

  test('sliders should contain non null groups', () {
    final groups = <String>['test1', 'test2', 'test3', 'test4', 'test5'];
    final model = WeightViewModel(groupNames: groups);

    final groupsAreNotNull = model.weightController.every(
      (element) => element.next != null && element.previous != null,
    );

    expect(groupsAreNotNull, isTrue);
  });

  test('sliders should have reference to the same group', () {
    final groups = <String>['test1', 'test2', 'test3', 'test4', 'test5'];
    final model = WeightViewModel(groupNames: groups);

    List<List<RubricGroup>> groupPair = [];
    model.weightController.fold<Slider>(
      null,
      (prev, current) {
        if (prev != null) {
          groupPair.add([prev.next, current.previous]);
        }

        return current;
      },
    );

    expect(
      groupPair.every(
        (pair) => pair.first.hashCode == pair.last.hashCode,
      ),
      isTrue,
    );
  });
}
