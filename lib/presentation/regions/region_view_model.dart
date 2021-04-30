import 'package:flutter/foundation.dart';

import 'package:rubric/domain/weight/rubric_region.dart';
import 'package:rubric/domain/weight/slider.dart';
import 'package:rubric/domain/weight/weight_controller.dart';

class RegionViewModel extends ChangeNotifier {
  final WeightController _controller;
  bool isAllLocked() => getRegions.every((region) => region.isLocked);

  RegionViewModel({@required WeightController controller})
      : _controller = controller;

  List<RubricRegion> get getRegions => _controller.getRegions();

  void moveSlider({
    @required Slider slider,
    @required ScrollPosition scrollPosition,
  }) {
    _controller.moveSlider(slider: slider, scrollPosition: scrollPosition);
    notifyListeners();
  }

  /// Build a list of [RubricRegion]s separated by [Slider]s
  ///
  /// Normally used to build a list of [Widget]s to be used inside of the [build]
  /// method of a [StatelessWidget] or [StatefullWidget]
  List<T> mapController<T>({
    @required T Function(Slider slider) sliderBuilder,
    @required T Function(RubricRegion region) regionBuilder,
  }) {
    final sliders = _controller.toList();
    final regions = _controller.getRegions();

    int index = 0;
    return List<T>.from(regions.map((region) {
      final sliderExists = sliders.length >= index + 1;
      if (sliderExists) {
        final slider = sliders[index];
        final result = [regionBuilder(region), sliderBuilder(slider)];
        index++;
        return result;
      }
      index++;
      return [regionBuilder(region)];
    }).expand((e) => e));
  }
}
