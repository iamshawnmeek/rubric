import 'package:flutter/foundation.dart';

import 'package:double_linked_list/double_linked_list.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rubric/domain/weight/rubric_group.dart';
import 'package:rubric/domain/weight/slider.dart';
import 'package:rubric/domain/weight/weight_controller.dart';

void main() {
  group('initialization', () {
    test('should create a WeightController', () {
      final regionNames = <String>['region1', 'region2', 'region3'];
      final controller = WeightController.fromNames(regionNames);

      expect(controller, isNotNull);
    });

    test('controller should contain sliders', () {
      final regionNames = <String>[
        'region1',
        'region2',
        'region3',
        'region4',
      ];
      final sliderCount = regionNames.length - 1;
      final controller = WeightController.fromNames(regionNames);

      expect(controller.length, sliderCount);
    });

    test('sliders should contain non null regionNames', () {
      final regionNames = <String>[
        'region1',
        'region2',
        'region3',
        'region4',
        'region5'
      ];
      final controller = WeightController.fromNames(regionNames);

      final groupsAreNotNull = controller.every(
        (element) =>
            element.regionAfter != null && element.regionBefore != null,
      );

      expect(groupsAreNotNull, isTrue);
    });

    test('sliders should have reference to the same group', () {
      final regionNames = <String>[
        'region1',
        'region2',
        'region3',
        'region4',
        'region5'
      ];
      final controller = WeightController.fromNames(regionNames);

      List<List<RubricGroup>> groupPair = [];
      controller.fold<Slider>(
        null,
        (prev, current) {
          if (prev != null) {
            groupPair.add([prev.regionAfter, current.regionBefore]);
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

  group('#getRegions', () {
    test('should get unique groups', () {
      final regionNames = <String>[
        'region0',
        'region1',
        'region2',
        'region3',
        'region4'
      ];
      final controller = WeightController.fromNames(regionNames);

      final groups = controller.getRegions();

      expect(groups.map((group) => group.title), regionNames);
    });
  });

  group('#moveSlider', () {
    ScrollPosition getAdjustedPosition({
      @required int sliderCount,
      @required double initialWeight,
      @required double adjustment,
      @required int sliderIndex,
    }) {
      final positions = List.generate(
        sliderCount,
        (index) => ScrollPosition(initialWeight * (index + 1)),
      );

      final positionToAdjust = positions.removeAt(sliderIndex);
      final currentValue = positionToAdjust.value;

      return ScrollPosition(currentValue + adjustment);
    }

    void testMoveSlider({
      @required WeightController controller,
      @required List<String> regionNames,
      @required ScrollPosition scrollPosition,
      @required void makeAssertions(Node<Slider> slider),
      @required Node<Slider> getSliderRef(),
      void lockRegions(Slider slider),
    }) {
      final sliderRef = getSliderRef();

      lockRegions?.call(sliderRef.content);

      controller.moveSlider(
        sliderRef: sliderRef,
        scrollPosition: scrollPosition,
      );

      makeAssertions(sliderRef);
    }

    test('unless moving would be negative', () {
      final regionNames = <String>[
        'region0',
        'region1',
        'region2',
        'region3',
        'region4'
      ];
      final controller = WeightController.fromNames(regionNames);
      final initialWeight = 100 / regionNames.length;
      final sliderIndex = 0;
      final adjustedPosition = getAdjustedPosition(
        initialWeight: initialWeight,
        sliderCount: regionNames.length - 1,
        sliderIndex: sliderIndex,
        adjustment: -(initialWeight + .01),
      );

      testMoveSlider(
        controller: controller,
        regionNames: regionNames,
        scrollPosition: adjustedPosition,
        getSliderRef: () => controller[sliderIndex],
        makeAssertions: (adjustedRef) {
          final adjustedSlider = adjustedRef.content;
          final region1 = adjustedSlider.regionBefore;
          final region2 = adjustedSlider.regionAfter;

          expect(region1.weight, initialWeight);
          expect(region2.weight, initialWeight);
        },
      );
    });

    group('with no locks', () {
      group('first slider', () {
        test('should reduce region1 and increase region2', () {
          final regionNames = <String>[
            'region0',
            'region1',
            'region2',
            'region3',
            'region4'
          ];
          final controller = WeightController.fromNames(regionNames);
          final initialWeight = 100 / regionNames.length;
          final sliderIndex = 0;
          final adjustedPosition = getAdjustedPosition(
            initialWeight: initialWeight,
            sliderCount: regionNames.length - 1,
            sliderIndex: sliderIndex,
            adjustment: -15,
          );

          testMoveSlider(
            controller: controller,
            regionNames: regionNames,
            scrollPosition: adjustedPosition,
            getSliderRef: () => controller[sliderIndex],
            makeAssertions: (adjustedRef) {
              final adjustedSlider = adjustedRef.content;
              final region1 = adjustedSlider.regionBefore;
              final region2 = adjustedSlider.regionAfter;

              expect(region1.weight, initialWeight - 15);
              expect(region2.weight, initialWeight + 15);
            },
          );
        });

        test('should increase region1 and reduce region2', () {
          final regionNames = <String>[
            'region0',
            'region1',
            'region2',
            'region3',
            'region4'
          ];
          final controller = WeightController.fromNames(regionNames);
          final initialWeight = 100 / regionNames.length;
          final sliderIndex = 0;
          final adjustedPosition = getAdjustedPosition(
            initialWeight: initialWeight,
            sliderCount: regionNames.length - 1,
            adjustment: 15,
            sliderIndex: sliderIndex,
          );

          testMoveSlider(
            controller: controller,
            regionNames: regionNames,
            scrollPosition: adjustedPosition,
            getSliderRef: () => controller[sliderIndex],
            makeAssertions: (adjustedRef) {
              final adjustedSlider = adjustedRef.content;
              final region1 = adjustedSlider.regionBefore;
              final region2 = adjustedSlider.regionAfter;

              expect(region1.weight, initialWeight + 15);
              expect(region2.weight, initialWeight - 15);
            },
          );
        });
      });

      group('middle slider', () {
        test('should reduce region1 and increase region2', () {
          final regionNames = <String>[
            'region0',
            'region1',
            'region2',
            'region3',
            'region4',
            'region5'
          ];
          final controller = WeightController.fromNames(regionNames);
          final initialWeight = 100 / regionNames.length;
          final sliderIndex = 2;
          final adjustedPosition = getAdjustedPosition(
            adjustment: -15,
            sliderIndex: sliderIndex,
            initialWeight: initialWeight,
            sliderCount: regionNames.length - 1,
          );

          testMoveSlider(
            controller: controller,
            regionNames: regionNames,
            scrollPosition: adjustedPosition,
            getSliderRef: () => controller[sliderIndex],
            makeAssertions: (adjustedRef) {
              final adjustedSlider = adjustedRef.content;
              final region1 = adjustedSlider.regionBefore;
              final region2 = adjustedSlider.regionAfter;

              expect(region1.weight, initialWeight - 15);
              expect(region2.weight, initialWeight + 15);
            },
          );
        });

        test('should increase region1 and reduce region2', () {
          final regionNames = <String>[
            'region0',
            'region1',
            'region2',
            'region3',
            'region4',
            'region5'
          ];
          final controller = WeightController.fromNames(regionNames);
          final initialWeight = 100 / regionNames.length;
          final sliderIndex = 2;
          final adjustedPosition = getAdjustedPosition(
            adjustment: 15,
            sliderIndex: sliderIndex,
            initialWeight: initialWeight,
            sliderCount: regionNames.length - 1,
          );

          testMoveSlider(
            controller: controller,
            regionNames: regionNames,
            scrollPosition: adjustedPosition,
            getSliderRef: () => controller[sliderIndex],
            makeAssertions: (adjustedRef) {
              final adjustedSlider = adjustedRef.content;
              final region1 = adjustedSlider.regionBefore;
              final region2 = adjustedSlider.regionAfter;

              expect(region1.weight, initialWeight + 15);
              expect(region2.weight, initialWeight - 15);
            },
          );
        });
      });

      group('last slider', () {
        test('should reduce region1 and increase region2', () {
          final regionNames = <String>[
            'region0',
            'region1',
            'region2',
            'region3',
            'region4'
          ];
          final controller = WeightController.fromNames(regionNames);
          final initialWeight = 100 / regionNames.length;
          final sliderCount = regionNames.length - 1;
          final sliderIndex = sliderCount - 1;
          final adjustedPosition = getAdjustedPosition(
            adjustment: -15,
            sliderIndex: sliderIndex,
            initialWeight: initialWeight,
            sliderCount: sliderCount,
          );

          testMoveSlider(
            controller: controller,
            regionNames: regionNames,
            scrollPosition: adjustedPosition,
            getSliderRef: () => controller[sliderIndex],
            makeAssertions: (adjustedRef) {
              final adjustedSlider = adjustedRef.content;
              final region1 = adjustedSlider.regionBefore;
              final region2 = adjustedSlider.regionAfter;

              expect(region1.weight, initialWeight - 15);
              expect(region2.weight, initialWeight + 15);
            },
          );
        });

        test('should increase region1 and reduce region2', () {
          final regionNames = <String>[
            'region0',
            'region1',
            'region2',
            'region3',
            'region4'
          ];
          final controller = WeightController.fromNames(regionNames);
          final initialWeight = 100 / regionNames.length;
          final sliderCount = regionNames.length - 1;
          final sliderIndex = sliderCount - 1;
          final adjustedPosition = getAdjustedPosition(
            adjustment: 15,
            sliderIndex: sliderIndex,
            initialWeight: initialWeight,
            sliderCount: sliderCount,
          );

          testMoveSlider(
            controller: controller,
            regionNames: regionNames,
            scrollPosition: adjustedPosition,
            getSliderRef: () => controller[sliderIndex],
            makeAssertions: (adjustedRef) {
              final adjustedSlider = adjustedRef.content;
              final region1 = adjustedSlider.regionBefore;
              final region2 = adjustedSlider.regionAfter;

              expect(region1.weight, initialWeight + 15);
              expect(region2.weight, initialWeight - 15);
            },
          );
        });
      });
    });

    group('with locks', () {
      group('should move next available slider', () {
        test('unless none are available in direction above', () {
          final regionNames = <String>[
            'region0',
            'region1',
            'region2',
            'region3',
            'region4'
          ];
          final controller = WeightController.fromNames(regionNames);
          final initialWeight = 100 / regionNames.length;
          final sliderIndex = 0;
          final adjustedPosition = getAdjustedPosition(
            adjustment: -15,
            sliderIndex: sliderIndex,
            initialWeight: initialWeight,
            sliderCount: regionNames.length - 1,
          );

          testMoveSlider(
            controller: controller,
            regionNames: regionNames,
            scrollPosition: adjustedPosition,
            getSliderRef: () => controller.first,
            lockRegions: (slider) {
              final firstRegion = slider.regionBefore;

              firstRegion.lock();
            },
            makeAssertions: (adjustedRef) {
              final adjustedSlider = adjustedRef.content;
              final region1 = adjustedSlider.regionBefore;
              final region2 = adjustedSlider.regionAfter;

              expect(region1.weight, initialWeight);
              expect(region2.weight, initialWeight);
            },
          );
        });

        test('unless none are available in direction below', () {
          final regionNames = <String>[
            'region0',
            'region1',
            'region2',
            'region3',
            'region4'
          ];
          final controller = WeightController.fromNames(regionNames);
          final initialWeight = 100 / regionNames.length;
          final sliderCount = regionNames.length - 1;
          final sliderIndex = sliderCount - 1;
          final adjustedPosition = getAdjustedPosition(
            adjustment: -15,
            sliderIndex: sliderIndex,
            initialWeight: initialWeight,
            sliderCount: sliderCount,
          );

          testMoveSlider(
            controller: controller,
            regionNames: regionNames,
            scrollPosition: adjustedPosition,
            getSliderRef: () => controller[sliderIndex],
            lockRegions: (slider) {
              final lastRegion = slider.regionAfter;

              lastRegion.lock();
            },
            makeAssertions: (adjustedRef) {
              final adjustedSlider = adjustedRef.content;
              final region1 = adjustedSlider.regionBefore;
              final region2 = adjustedSlider.regionAfter;

              expect(region1.weight, initialWeight);
              expect(region2.weight, initialWeight);
            },
          );
        });

        /// Visualization
        /// ----- Region: region0 -----
        /// ------ Slider: 0 --------
        /// ----- Region: region1 ----- x expect to reduce in size
        /// ------ Slider: 1 --------
        /// ----- Region: region2 ----- x region to lock
        /// ------ Slider: 2 -------- x slider to move up
        /// ----- Region: region3 ----- x expect to increase in size
        /// ------ Slider: 3 --------
        /// ----- Region: region4 -----
        test('in direction above', () {
          final regionNames = <String>[
            'region0',
            'region1',
            'region2',
            'region3',
            'region4'
          ];
          final controller = WeightController.fromNames(regionNames);
          final initialWeight = 100 / regionNames.length;
          final sliderIndex = 2;
          final adjustedPosition = getAdjustedPosition(
            adjustment: -15,
            sliderIndex: sliderIndex,
            initialWeight: initialWeight,
            sliderCount: regionNames.length - 1,
          );

          testMoveSlider(
            controller: controller,
            regionNames: regionNames,
            scrollPosition: adjustedPosition,
            getSliderRef: () => controller[sliderIndex],
            lockRegions: (adjustedSlider) {
              final regionToLock = adjustedSlider.regionBefore;

              regionToLock.lock();
            },
            makeAssertions: (slider2Ref) {
              // Slider 1
              // regionBefore: region1
              // regionAfter: region2
              final slider1 = slider2Ref.previous.content;
              final region1 = slider1.regionBefore;
              // Slider 2
              // regionBefore: region2
              // regionAfter: region3
              final slider2 = slider2Ref.content;
              final region2 = slider2.regionBefore;
              final region3 = slider2.regionAfter;

              // Assertions for region 1
              expect(region1.title, 'region1');
              expect(region1.weight, initialWeight - 15);

              // Assertions for region 2
              expect(region2.title, 'region2');
              expect(region2.isLocked, isTrue);

              // Assertions for region 3
              expect(region3.title, 'region3');
              expect(region3.weight, initialWeight + 15);
            },
          );
        });

        /// Visualization
        /// ----- Region: region0 -----
        /// ------ Slider: 0 --------
        /// ----- Region: region1 -----
        /// ------ Slider: 1 --------
        /// ----- Region: region2 ----- x expect to increase in size
        /// ------ Slider: 2 -------- x slider to move down
        /// ----- Region: region3 -----  x region to lock
        /// ------ Slider: 3 --------
        /// ----- Region: region4 ----- x expect to reduce in size
        test('in direction below', () {
          final regionNames = <String>[
            'region0',
            'region1',
            'region2',
            'region3',
            'region4'
          ];
          final controller = WeightController.fromNames(regionNames);
          final initialWeight = 100 / regionNames.length;
          final sliderIndex = 2;
          final adjustedPosition = getAdjustedPosition(
            adjustment: 15,
            sliderIndex: sliderIndex,
            initialWeight: initialWeight,
            sliderCount: regionNames.length - 1,
          );

          testMoveSlider(
            controller: controller,
            regionNames: regionNames,
            scrollPosition: adjustedPosition,
            getSliderRef: () => controller[sliderIndex],
            lockRegions: (adjustedSlider) {
              final regionToLock = adjustedSlider.regionAfter;

              regionToLock.lock();
            },
            makeAssertions: (slider2Ref) {
              // Slider 2
              // regionBefore: region2
              // regionAfter: region3
              final slider2 = slider2Ref.content;
              final region2 = slider2.regionBefore;
              // Slider 3
              // regionBefore: region3
              // regionAfter: region4
              final slider3 = slider2Ref.next.content;
              final region3 = slider3.regionBefore;
              final region4 = slider3.regionAfter;

              // Assertions for region 2
              expect(region2.title, 'region2');
              expect(region2.weight, initialWeight + 15);

              // Assertions for region 3
              expect(region3.title, 'region3');
              expect(region3.isLocked, isTrue);

              // Assertions for region 4
              expect(region4.title, 'region4');
              expect(region4.weight, initialWeight - 15);
            },
          );
        });
      });
    });
  });
}
