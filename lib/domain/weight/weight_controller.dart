import 'package:flutter/foundation.dart';

import 'package:double_linked_list/double_linked_list.dart';

import 'package:rubric/domain/weight/rubric_group.dart';
import 'package:rubric/domain/weight/slider.dart';

class WeightController extends DoubleLinkedList<Slider> {
  WeightController.fromIterable(Iterable<Slider> contents)
      : super.fromIterable(contents);

  /// Traverse to the node from the beginning until reaching the supplied index
  operator [](int i) {
    Node<Slider> node = begin;

    for (int x = 0; x <= i; x++) {
      node = node.next;
    }

    return node;
  }

  List<RubricGroup> getRegions() => toList()
      .expand(
        (e) => [
          e.regionBefore,
          e.regionAfter,
        ],
      )
      .toSet() // Remove duplicates
      .toList();

  void moveSlider({
    @required Node<Slider> sliderRef,
    @required ScrollPosition scrollPosition,
  }) {
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

  Slider _getNonLockedSlider({
    @required Node<Slider> currentRef,
    @required Node<Slider> getSliderRef(Node<Slider> ref),
    @required RubricGroup getRegion(Slider slider),
  }) {
    Node<Slider> pointer = currentRef;

    bool atEnd() => pointer.isBegin || pointer.isEnd;
    bool groupIsLocked() => getRegion(pointer.content).isLocked;

    while (!atEnd() && groupIsLocked()) {
      pointer = getSliderRef(pointer);
    }

    return atEnd() ? null : pointer.content;
  }

  static WeightController fromNames(List<String> groupNames) {
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
          regionAfter: current,
          regionBefore: previous,
          initial: ScrollPosition(groupWeight * sliderIndex),
        );

        sliders.add(slider);
      }

      return current;
    });

    return sliders;
  }
}
