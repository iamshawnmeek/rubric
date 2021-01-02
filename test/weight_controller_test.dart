import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/weight/rubric_group.dart';
import 'package:rubric/weight/slider.dart';
import 'package:rubric/weight/weight_controller.dart';

void main() {
  group('initialization', () {
    test('should create a WeightController', () {
      final groups = <String>['group1', 'group2', 'group3'];
      final controller = WeightController.fromGroupNames(groups);

      expect(controller, isNotNull);
    });

    test('controller should contain sliders', () {
      final groups = <String>['group1', 'group2', 'group3', 'group4'];
      final controller = WeightController.fromGroupNames(groups);

      final sliderCount = groups.length - 1;

      expect(controller.length, sliderCount);
    });

    test('sliders should contain non null groups', () {
      final groups = <String>['group1', 'group2', 'group3', 'group4', 'group5'];
      final controller = WeightController.fromGroupNames(groups);

      final groupsAreNotNull = controller.every(
        (element) => element.next != null && element.previous != null,
      );

      expect(groupsAreNotNull, isTrue);
    });

    test('sliders should have reference to the same group', () {
      final groups = <String>['group1', 'group2', 'group3', 'group4', 'group5'];
      final controller = WeightController.fromGroupNames(groups);

      List<List<RubricGroup>> groupPair = [];
      controller.fold<Slider>(
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
  });

  group('#moveSlider', () {
    List<double> getPositions({
      @required int length,
      @required double initialWeight,
    }) {
      return List.generate(length, (index) => initialWeight * (index + 1));
    }

    void testMoveSlider({
      @required WeightController controller,
      @required List<String> groups,
      @required List<double> positions,
      @required void makeAssertions(Slider slider),
      @required Slider getSlider(),
      void lockRegions(),
    }) {
      assert(positions.length == groups.length - 1);

      final allSliders = controller.toList();
      final sliderPositions = allSliders.fold<Map<Slider, double>>(
        {}, // start with an empty Map
        (acc, curr) {
          acc[curr] = positions[acc.length];
          return acc;
        },
      );

      lockRegions?.call();

      final sliderToMove = getSlider();
      controller.moveSlider(
        slider: sliderToMove,
        sliderPositions: sliderPositions,
      );

      makeAssertions(sliderToMove);
    }

    group('with no locks', () {
      group('first slider', () {
        test('should reduce group1 and increase group2', () {
          final groups = <String>['test1', 'test2', 'test3', 'test4', 'test5'];
          final controller = WeightController.fromGroupNames(groups);
          final initialWeight = 100 / groups.length;
          final adjustedIndex = 0;
          final positions = getPositions(
            initialWeight: initialWeight,
            length: groups.length - 1,
          );
          final adjustedPosition = positions.removeAt(adjustedIndex) - 15;
          positions.insert(adjustedIndex, adjustedPosition);

          testMoveSlider(
            controller: controller,
            groups: groups,
            positions: positions,
            getSlider: () => controller.first.content,
            makeAssertions: (adjustedSlider) {
              final group1 = adjustedSlider.previous;
              final group2 = adjustedSlider.next;

              expect(group1.weight, lessThan(initialWeight));
              expect(group2.weight, greaterThan(initialWeight));
            },
          );
        });

        test('should increase group1 and reduce group2', () {
          final groups = <String>['test1', 'test2', 'test3', 'test4', 'test5'];
          final controller = WeightController.fromGroupNames(groups);
          final initialWeight = 100 / groups.length;
          final adjustedIndex = 0;
          final positions = getPositions(
            initialWeight: initialWeight,
            length: groups.length - 1,
          );
          final adjustedPosition = positions.removeAt(adjustedIndex) + 15;
          positions.insert(adjustedIndex, adjustedPosition);

          testMoveSlider(
            controller: controller,
            groups: groups,
            positions: positions,
            getSlider: () => controller.first.content,
            makeAssertions: (adjustedSlider) {
              final group1 = adjustedSlider.previous;
              final group2 = adjustedSlider.next;

              expect(group1.weight, greaterThan(initialWeight));
              expect(group2.weight, lessThan(initialWeight));
            },
          );
        });
      });

      group('middle slider', () {
        test('should reduce group1 and increase group2', () {
          final groups = <String>['test1', 'test2', 'test3', 'test4', 'test5'];
          final controller = WeightController.fromGroupNames(groups);
          final initialWeight = 100 / groups.length;
          final adjustedIndex = 2;
          final positions = getPositions(
            initialWeight: initialWeight,
            length: groups.length - 1,
          );
          final adjustedPosition = positions.removeAt(adjustedIndex) - 15;
          positions.insert(adjustedIndex, adjustedPosition);

          testMoveSlider(
            controller: controller,
            groups: groups,
            positions: positions,
            getSlider: () => controller.toList()[adjustedIndex],
            makeAssertions: (adjustedSlider) {
              final group1 = adjustedSlider.previous;
              final group2 = adjustedSlider.next;

              expect(group1.weight, lessThan(initialWeight));
              expect(group2.weight, greaterThan(initialWeight));
            },
          );
        });

        test('should increase group1 and reduce group2', () {
          final groups = <String>['test1', 'test2', 'test3', 'test4', 'test5'];
          final controller = WeightController.fromGroupNames(groups);
          final initialWeight = 100 / groups.length;
          final adjustedIndex = 2;
          final positions = getPositions(
            initialWeight: initialWeight,
            length: groups.length - 1,
          );
          final adjustedPosition = positions.removeAt(adjustedIndex) + 15;
          positions.insert(adjustedIndex, adjustedPosition);

          testMoveSlider(
            controller: controller,
            groups: groups,
            positions: positions,
            getSlider: () => controller.toList()[adjustedIndex],
            makeAssertions: (adjustedSlider) {
              final group1 = adjustedSlider.previous;
              final group2 = adjustedSlider.next;

              expect(group1.weight, greaterThan(initialWeight));
              expect(group2.weight, lessThan(initialWeight));
            },
          );
        });
      });

      group('last slider', () {
        test('should reduce group1 and increase group2', () {
          final groups = <String>['test1', 'test2', 'test3', 'test4', 'test5'];
          final controller = WeightController.fromGroupNames(groups);
          final initialWeight = 100 / groups.length;
          final positions = getPositions(
            initialWeight: initialWeight,
            length: groups.length - 1,
          );
          final adjustedPosition = positions.removeLast() - 15;
          positions.add(adjustedPosition);

          testMoveSlider(
            controller: controller,
            groups: groups,
            positions: positions,
            getSlider: () => controller.last.content,
            makeAssertions: (adjustedSlider) {
              final group1 = adjustedSlider.previous;
              final group2 = adjustedSlider.next;

              expect(group1.weight, lessThan(initialWeight));
              expect(group2.weight, greaterThan(initialWeight));
            },
          );
        });

        test('should increase group1 and reduce group2', () {
          final groups = <String>['test1', 'test2', 'test3', 'test4', 'test5'];
          final controller = WeightController.fromGroupNames(groups);
          final initialWeight = 100 / groups.length;
          final positions = getPositions(
            initialWeight: initialWeight,
            length: groups.length - 1,
          );
          final adjustedPosition = positions.removeLast() + 15;
          positions.add(adjustedPosition);

          testMoveSlider(
            controller: controller,
            groups: groups,
            positions: positions,
            getSlider: () => controller.last.content,
            makeAssertions: (adjustedSlider) {
              final group1 = adjustedSlider.previous;
              final group2 = adjustedSlider.next;

              expect(group1.weight, greaterThan(initialWeight));
              expect(group2.weight, lessThan(initialWeight));
            },
          );
        });
      });
    });

    group('with locks', () {
      group('should move next available slider', () {
        test('unless none are available in direction above', () {
          final groups = <String>['test1', 'test2', 'test3', 'test4', 'test5'];
          final controller = WeightController.fromGroupNames(groups);
          final initialWeight = 100 / groups.length;
          final adjustedIndex = 0;
          final positions = getPositions(
            initialWeight: initialWeight,
            length: groups.length - 1,
          );
          final adjustedPosition = positions.removeAt(adjustedIndex) - 15;
          positions.insert(adjustedIndex, adjustedPosition);

          testMoveSlider(
            controller: controller,
            groups: groups,
            positions: positions,
            getSlider: () => controller.first.content,
            lockRegions: () {
              final firstRegion = controller.first.content.previous;

              firstRegion.lock();
            },
            makeAssertions: (adjustedSlider) {
              final group1 = adjustedSlider.previous;
              final group2 = adjustedSlider.next;

              expect(group1.weight, initialWeight);
              expect(group2.weight, initialWeight);
            },
          );
        });

        test('unless none are available in direction below', () {
          final groups = <String>['test1', 'test2', 'test3', 'test4', 'test5'];
          final controller = WeightController.fromGroupNames(groups);
          final initialWeight = 100 / groups.length;
          final positions = getPositions(
            initialWeight: initialWeight,
            length: groups.length - 1,
          );
          final adjustedPosition = positions.removeLast() - 15;
          positions.add(adjustedPosition);

          testMoveSlider(
            controller: controller,
            groups: groups,
            positions: positions,
            getSlider: () => controller.last.content,
            lockRegions: () {
              final lastRegion = controller.last.content.next;

              lastRegion.lock();
            },
            makeAssertions: (adjustedSlider) {
              final group1 = adjustedSlider.previous;
              final group2 = adjustedSlider.next;

              expect(group1.weight, initialWeight);
              expect(group2.weight, initialWeight);
            },
          );
        });
      });
    });
  });
}
