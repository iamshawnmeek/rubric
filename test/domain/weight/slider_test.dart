import 'package:flutter_test/flutter_test.dart';

import 'package:rubric/domain/weight/rubric_region.dart';
import 'package:rubric/domain/weight/slider.dart';

void main() {
  group('#handleAdjustment', () {
    const weight = 50.0;
    Slider slider;

    setUp(() {
      slider = Slider(
        regionBefore: RubricRegion(
          title: 'region1',
          weight: weight,
        ),
        regionAfter: RubricRegion(
          title: 'region2',
          weight: weight,
        ),
        initial: const ScrollPosition(50),
      );
    });
    test('should decrease scroll position with upward delta', () {
      expect(slider.scrollPosition, 50);

      slider.handleAdjustment(
        const ScrollDelta(direction: Direction.up, value: 50),
      );

      expect(slider.scrollPosition, 0);
    });

    test('should increase scroll position with upward delta', () {
      expect(slider.scrollPosition, 50);

      slider.handleAdjustment(
        const ScrollDelta(direction: Direction.down, value: 50),
      );

      expect(slider.scrollPosition, 100);
    });
  });

  group('#getScrollDelta', () {
    const weight = 50.0;
    Slider slider;

    setUp(() {
      slider = Slider(
        regionBefore: RubricRegion(
          title: 'region1',
          weight: weight,
        ),
        regionAfter: RubricRegion(
          title: 'region2',
          weight: weight,
        ),
        initial: const ScrollPosition(50),
      );
    });

    test('should return offset with non-negative lower scroll position', () {
      const scrollValue = 10.0;
      final delta = slider.getScrollDelta(const ScrollPosition(scrollValue));

      expect(delta.direction, Direction.up);
      expect(delta.value, 40);
    });

    test('should return offset with non-negative higher scroll position', () {
      const scrollValue = 70.0;
      final delta = slider.getScrollDelta(const ScrollPosition(scrollValue));

      expect(delta.direction, Direction.down);
      expect(delta.value, 20);
    });
  });
}
