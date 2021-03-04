import 'package:flutter_test/flutter_test.dart';

import 'package:rubric/domain/weight/rubric_region.dart';

void main() {
  const initialWeight = 50.0;
  RubricRegion region;
  setUp(() {
    region = RubricRegion(title: 'region1', weight: initialWeight);
  });

  tearDown(() {
    region.dispose();
  });

  group('isLocked setter', () {
    test('should only update when the new value is different', () {
      int updateCount = 0;
      region.addListener(() => updateCount++);
      expect(updateCount, 0);
      expect(region.isLocked, isFalse);

      region.isLocked = false;
      expect(updateCount, 0);
      expect(region.isLocked, isFalse);

      region.isLocked = true;
      expect(updateCount, 1);
      expect(region.isLocked, isTrue);
    });
  });

  group('weight setter should only update when', () {
    test('the new value is different', () {
      int updateCount = 0;
      region.addListener(() => updateCount++);
      expect(updateCount, 0);
      expect(region.weight, initialWeight);

      region.weight = initialWeight;
      expect(updateCount, 0);
      expect(region.weight, initialWeight);

      region.weight = initialWeight + 5.2;
      expect(updateCount, 1);
      expect(region.weight, initialWeight + 5.2);
    });

    test('is not locked', () {
      int updateCount = 0;
      double previousWeight = initialWeight;
      region.addListener(() {
        if (previousWeight != region.weight) {
          previousWeight = region.weight;
          updateCount++;
        }
      });
      expect(updateCount, 0);
      expect(region.isLocked, isFalse);
      expect(region.weight, initialWeight);

      region.lock();
      region.weight = initialWeight;
      expect(updateCount, 0);
      expect(region.isLocked, isTrue);
      expect(region.weight, initialWeight);

      region.unlock();
      region.weight = initialWeight + 5.2;
      expect(updateCount, 1);
      expect(region.isLocked, isFalse);
      expect(region.weight, initialWeight + 5.2);
    });

    test('value is greater than 0', () {
      expect(region.weight, initialWeight);

      region.weight = -1.2;
      expect(region.weight, initialWeight);

      region.weight = 0.0;
      expect(region.weight, isZero);
    });
  });

  group('#increaseWeight', () {
    test('should increase the weight by the value passed in', () {
      expect(region.weight, initialWeight);
      const testValue = 10.0;

      region.increaseWeight(testValue);

      expect(region.weight, initialWeight + testValue);
    });
  });

  group('#decreaseWeight', () {
    test('should decrease the weight by the value passed in', () {
      expect(region.weight, initialWeight);
      const testValue = 10.0;

      region.decreaseWeight(testValue);

      expect(region.weight, initialWeight - testValue);
    });
  });
}
