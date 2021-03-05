import 'package:flutter/foundation.dart';

import 'package:rubric/domain/weight/rubric_region.dart';
import 'package:rubric/domain/weight/slider.dart';
import 'package:rubric/domain/weight/weight_controller.dart';

class RegionViewModel {
  final WeightController controller;
  bool isAllLocked = false;

  RegionViewModel({@required this.controller});

  /// Build a list of [RubricRegion]s separated by [Slider]s
  ///
  /// Normally used to build a list of [Widget]s to be used inside of the [build]
  /// method of a [StatelessWidget] or [StatefullWidget]
  List<T> mapController<T>({
    @required T fromSlider(Slider slider),
    @required T fromRegion(RubricRegion slider),
  }) {
    final sliders = controller.toList();
    final regions = controller.getRegions();

    int index = 0;
    return List<T>.from(regions.map((region) {
      final sliderExists = sliders.length >= index + 1;
      if (sliderExists) {
        final slider = sliders[index];
        final result = [fromRegion(region), fromSlider(slider)];
        index++;
        return result;
      }
      index++;
      return [fromRegion(region)];
    }).expand((e) => e));
  }
}
