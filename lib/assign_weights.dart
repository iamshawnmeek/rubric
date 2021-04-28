import 'dart:math';
import 'package:flutter/material.dart' hide Slider, ScrollPosition;
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/rubric_lock.dart';
import 'package:rubric/domain/weight/rubric_region.dart';
import 'package:rubric/domain/weight/slider.dart';
import 'package:rubric/presentation/regions/region_view_model.dart';
import 'package:rubric/typography/body_one.dart';
import 'package:rubric/typography/headline_one.dart';
import 'typography/body_weights.dart';

class AssignWeights extends StatefulWidget {
  final RegionViewModel model;

  const AssignWeights({
    @required this.model,
    Key key,
  }) : super(key: key);

  @override
  _AssignWeightsState createState() => _AssignWeightsState();
}

class _AssignWeightsState extends State<AssignWeights> {
  @override
  void initState() {
    super.initState();
    widget.model.addListener(updateState);
  }

  @override
  void dispose() {
    widget.model.removeListener(updateState);
    super.dispose();
  }

  void updateState() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 36),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: HeadlineOne('Assign Weights'),
                ),
                SizedBox(height: 24),
                Expanded(
                  child: _bodyContent(),
                ),
                SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bodyContent() {
    return ClipRRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const sliderHeight = 30.0;
          final height = constraints.maxHeight;
          final regionCount = widget.model.getRegions.length;
          final sliderCount = regionCount - 1;
          final sliderOffsetPerRegion =
              sliderCount * sliderHeight / regionCount;

          return Container(
            child: Column(
              children: widget.model.mapController(
                sliderBuilder: (slider) {
                  return GestureDetector(
                    // onVerticalDragStart: (deets) => print('Start'),
                    // onVerticalDragEnd: (deets) => print('End'),
                    onVerticalDragUpdate: (deets) {
                      final yValue = slider.scrollPosition + deets.delta.dy / 8;
                      final scrollPosition = ScrollPosition(yValue);

                      widget.model.moveSlider(
                        slider: slider,
                        scrollPosition: scrollPosition,
                      );
                    },
                    child: WeightSlider(slider: slider),
                  );
                },
                regionBuilder: _buildRegion(
                  height: height,
                  sliderOffsetPerRegion: sliderOffsetPerRegion,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget Function(RubricRegion) _buildRegion({
    @required double height,
    @required double sliderOffsetPerRegion,
  }) {
    return (RubricRegion region) {
      final regionHeight = height * (region.weight / 100);
      final percentage = region.weight.roundToDouble();
      final heightMinusSliderOffset = regionHeight - sliderOffsetPerRegion;

      return Region(
        title: region.title,
        height: heightMinusSliderOffset,
        percentage: percentage,
      );
    };
  }
}

class WeightSlider extends StatelessWidget {
  const WeightSlider({
    Key key,
    @required this.slider,
  }) : super(key: key);

  final Slider slider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Stack(
        children: [
          Align(
            child: Container(
              height: 10,
              width: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: primaryLighter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Region extends StatefulWidget {
  final String title;
  final double height;
  final double percentage;

  const Region({
    Key key,
    @required this.title,
    @required this.height,
    @required this.percentage,
  }) : super(key: key);

  @override
  _RegionState createState() => _RegionState();
}

class _RegionState extends State<Region> {
  bool isLockActive = false;

  void toggleLock() => setState(() => isLockActive = !isLockActive);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: max(widget.height, 68), //max quantity of units, for now
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: primary,
      ),
      child: AnimatedCrossFade(
        crossFadeState: widget.percentage <= 15
            ? CrossFadeState.showFirst
            : CrossFadeState.showSecond,
        duration: const Duration(milliseconds: 300),
        firstChild: smallViewRegion(),
        secondChild: largeViewRegion(),
      ),
    );
  }

  Widget largeViewRegion() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Stack(
        // mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BodyOne(widget.title, fontSize: 21, color: primaryLighter),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 54),
                BodyOneWeights('${widget.percentage.toStringAsFixed(0)}%'),
                SizedBox(width: 10),
                RubricLock(
                  isActive: isLockActive,
                  onTap: toggleLock,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget smallViewRegion() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(left: 22, top: 9, bottom: 9, right: 7),
        child: Row(
          children: [
            Expanded(
              child: BodyOne(
                '${widget.percentage.toStringAsFixed(0)}%: ${widget.title}',
                fontSize: 21,
                color: primaryLighter,
              ),
            ),
            RubricLock(
              isActive: isLockActive,
              onTap: toggleLock,
            ),
          ],
        ),
      ),
    );
  }
}
