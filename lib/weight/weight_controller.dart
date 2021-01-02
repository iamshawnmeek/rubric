import 'package:double_linked_list/double_linked_list.dart';
import 'package:flutter/foundation.dart';
import 'package:rubric/weight/rubric_group.dart';
import 'package:rubric/weight/slider.dart';

class WeightController extends DoubleLinkedList<Slider> {
  WeightController.fromIterable(Iterable<Slider> contents)
      : super.fromIterable(contents);

  void moveSlider({
    @required Slider slider,
    @required Map<Slider, double> sliderPositions,
  }) {
    final currentRef = _getRef(slider);

    final previousSlider = _getPreviousNonLockedSlider(
      currentRef: currentRef,
      getSliderRef: (ref) => ref.previous,
      getRubricGroup: (slider) => slider.previous,
    );

    final nextSlider = _getPreviousNonLockedSlider(
      currentRef: currentRef,
      getSliderRef: (ref) => ref.next,
      getRubricGroup: (slider) => slider.next,
    );

    final canMove = previousSlider != null && nextSlider != null;
    if (canMove) {
      final previousPosition = sliderPositions[previousSlider];
      final nextPosition = sliderPositions[nextSlider];

      previousSlider.handleAdjustment(previousPosition);
      nextSlider.handleAdjustment(nextPosition);
    }
  }

  Slider _getPreviousNonLockedSlider({
    @required Node<Slider> currentRef,
    @required Node<Slider> getSliderRef(Node<Slider> ref),
    @required RubricGroup getRubricGroup(Slider slider),
  }) {
    Slider nonLockedSlider;
    Node<Slider> pointer = currentRef;

    while (pointer != null && nonLockedSlider == null) {
      final atEnd = pointer.isBegin || pointer.isEnd;
      groupIsLocked() => getRubricGroup(pointer.content).isLocked;

      if (!atEnd && groupIsLocked()) {
        pointer = getSliderRef(pointer); // check next ref
      } else {
        break; // set value to return
      }
    }

    return nonLockedSlider;
  }

  Node<Slider> _getRef(Slider slider) {
    return firstWhere(
      (storedSlider) => storedSlider.hashCode == slider.hashCode,
    );
  }

  static WeightController fromGroupNames(List<String> groupNames) {
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

    return WeightController.fromIterable(sliders);
  }

  static List<Slider> _buildSliders({
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
