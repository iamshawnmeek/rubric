import 'package:flutter_test/flutter_test.dart';
import 'package:rubric/domain/weight/weight_controller.dart';
import 'package:rubric/presentation/groups/group_view_model.dart';

void main() {
  group('#mapController', () {
    test('should separate groups with sliders', () {
      final regionNames = ['region0,', 'region1', 'region2', 'region3'];
      final controller = WeightController.fromNames(regionNames);

      final model = GroupViewModel(controller: controller);

      final result = model.mapController<int>(
        fromSlider: (slider) => slider.hashCode,
        fromGroup: (group) => group.hashCode,
      );

      expect(result.length, 7);
      expect(result.toSet().length, result.length); // no duplicates
    });
  });
}
