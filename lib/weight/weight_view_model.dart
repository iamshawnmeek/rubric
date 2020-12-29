import 'package:flutter/foundation.dart';
import 'package:rubric/weight/rubric_group.dart';
import 'package:rubric/weight/slider.dart';
import 'package:rubric/weight/weight_controller.dart';

class WeightViewModel extends ChangeNotifier {
  WeightController weightController;
  WeightViewModel({@required List<String> groupNames}) {
    _createController(groupNames);
  }

  void _createController(List<String> groupNames) {
    const maxValue = 100;
    final initialWeight = maxValue / groupNames.length;
    final rubricGroups = groupNames
        .map(
          (groupName) => RubricGroup(
            title: groupName,
            weight: initialWeight,
          ),
        )
        .toList();

    final sliders = _buildSliders(
      groups: rubricGroups,
      groupWeight: initialWeight,
    );

    weightController = WeightController.fromIterable(sliders);
  }

  List<Slider> _buildSliders({
    @required List<RubricGroup> groups,
    @required double groupWeight,
  }) {
    var sliders = <Slider>[];

    groups.fold(null, (previous, current) {
      final sliderIndex = sliders.length + 1;

      if (previous != null) {
        final slider = Slider(
          next: current,
          previous: previous,
          initialLocation: groupWeight * sliderIndex,
        );

        sliders.add(slider);
      }

      return current;
    });

    return sliders;
  }
}
