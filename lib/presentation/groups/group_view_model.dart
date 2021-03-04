import 'package:flutter/foundation.dart';

import 'package:rubric/domain/weight/rubric_group.dart';
import 'package:rubric/domain/weight/slider.dart';
import 'package:rubric/domain/weight/weight_controller.dart';

class GroupViewModel {
  final WeightController controller;
  bool isAllLocked = false;

  GroupViewModel({@required this.controller});

  /// Build a list of [RubricGroup]s separated by [Slider]s
  ///
  /// Normally used to build a list of [Widget]s to be used inside of the [build]
  /// method of a [StatelessWidget] or [StatefullWidget]
  List<T> mapController<T>({
    @required T fromSlider(Slider slider),
    @required T fromGroup(RubricGroup slider),
  }) {
    final sliders = controller.toList();
    final groups = controller.getRegions();

    int index = 0;
    return List<T>.from(groups.map((group) {
      final sliderExists = sliders.length >= index + 1;
      if (sliderExists) {
        final slider = sliders[index];
        final result = [fromGroup(group), fromSlider(slider)];
        index++;
        return result;
      }
      index++;
      return [fromGroup(group)];
    }).expand((e) => e));
  }
}
