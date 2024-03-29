import 'package:double_linked_list/double_linked_list.dart'; // not a way to fix unless modify package code
import 'package:rubric/domain/weight/rubric_region.dart';
import 'package:rubric/domain/weight/slider.dart';

class WeightController extends DoubleLinkedList<Slider> {
  WeightController.fromIterable(Iterable<Slider> contents)
      : super.fromIterable(contents);

  /// Traverse to the node from the beginning until reaching the supplied index
  Node<Slider> operator [](int i) {
    Node<Slider> node = begin;

    for (int x = 0; x <= i; x++) {
      node = node.next;
    }

    return node;
  }

  factory WeightController.fromNames(List<String> regionNames) {
    const maxValue = 100;
    final initialWeight = maxValue / regionNames.length;
    final rubricRegions = regionNames
        .map(
          (regionName) => RubricRegion(
            title: regionName,
            weight: initialWeight,
          ),
        )
        .toList();

    final sliders = _buildSliders(
      regions: rubricRegions,
      regionWeight: initialWeight,
    );

    return WeightController.fromIterable(sliders);
  }
  List<RubricRegion> getRegions() => toList()
      .expand(
        (e) => [
          e.regionBefore,
          e.regionAfter,
        ],
      )
      .toSet() // Remove duplicates
      .toList();

  void moveSlider({
    required Slider slider,
    required ScrollPosition scrollPosition,
  }) {
    final sliderRef = this.firstWhere((e) => e == slider);

    final previousSlider = _getNonLockedSlider(
      currentRef: sliderRef,
      getSliderRef: (ref) => ref.previous,
      getRegion: (slider) => slider.regionBefore,
    );

    final nextSlider = _getNonLockedSlider(
      currentRef: sliderRef,
      getSliderRef: (ref) => ref.next,
      getRegion: (slider) => slider.regionAfter,
    );

    final canMove = previousSlider != null && nextSlider != null;
    if (canMove) {
      final delta = sliderRef.content.getScrollDelta(scrollPosition);

      if (previousSlider != nextSlider) {
        previousSlider.handleAdjustment(delta);
        nextSlider.handleAdjustment(delta);
      } else {
        previousSlider.handleAdjustment(delta);
      }
    }
  }

  Slider? _getNonLockedSlider({
    required Node<Slider> currentRef,
    required Node<Slider> getSliderRef(Node<Slider> ref),
    required RubricRegion getRegion(Slider slider),
  }) {
    Node<Slider> pointer = currentRef;

    bool atEnd() => pointer.isBegin || pointer.isEnd;
    bool regionIsLocked() => getRegion(pointer.content).isLocked;

    while (!atEnd() && regionIsLocked()) {
      pointer = getSliderRef(pointer);
    }

    return atEnd() ? null : pointer.content;
  }

  static List<Slider> _buildSliders({
    required List<RubricRegion> regions,
    required double regionWeight,
  }) {
    final sliders = <Slider>[];

    regions.fold<RubricRegion?>(null, (previous, current) {
      final sliderIndex = sliders.length + 1;

      if (previous != null) {
        final slider = Slider(
          regionAfter: current,
          regionBefore: previous,
          initial: ScrollPosition(regionWeight * sliderIndex),
        );

        sliders.add(slider);
      }

      return current;
    });

    return sliders;
  }
}
