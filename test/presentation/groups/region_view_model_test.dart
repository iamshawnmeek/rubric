import 'package:flutter_test/flutter_test.dart';

import 'package:rubric/domain/weight/weight_controller.dart';
import 'package:rubric/presentation/regions/region_view_model.dart';

void main() {
  group('#mapController', () {
    test('should separate regions with sliders', () {
      final regionNames = ['region0,', 'region1', 'region2', 'region3'];
      final controller = WeightController.fromNames(regionNames);

      final model = RegionViewModel(controller: controller);

      final result = model.mapController(
        fromSlider: (slider) => slider.hashCode,
        fromRegion: (region) => region.hashCode,
      );

      expect(result.length, 7);
      expect(result.toSet().length, result.length); // no duplicates
    });
  });
}
