import 'package:flutter/material.dart' hide Slider;
import 'package:rubric/components/colors.dart';
import 'package:rubric/domain/weight/rubric_region.dart';
import 'package:rubric/domain/weight/slider.dart';
import 'package:rubric/presentation/regions/region_view_model.dart';
import 'package:rubric/typography/body_one.dart';
import 'package:rubric/typography/headline_one.dart';
import 'typography/body_weights.dart';

class AssignWeights extends StatelessWidget {
  final RegionViewModel model;

  const AssignWeights({
    @required this.model,
    Key key,
  }) : super(key: key);

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
    return LayoutBuilder(
      builder: (context, constraints) {
        const sliderHeight = 30.0;
        final height = constraints.maxHeight; //here
        final regionCount = model.controller.getRegions().length;
        final sliderCount = regionCount - 1;
        final sliderOffsetPerRegion = sliderCount * sliderHeight / regionCount;

        return Container(
          child: Column(
            children: model.mapController(
              sliderBuilder: (slider) {
                return WeightSlider(slider: slider);
              },
              regionBuilder: _buildRegion(
                height: height,
                sliderOffsetPerRegion: sliderOffsetPerRegion,
              ),
            ),
          ),
        );
      },
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
        data: region.title,
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

class Region extends StatelessWidget {
  final String data;
  final double height;
  final double percentage;

  const Region({
    Key key,
    @required this.data,
    @required this.height,
    @required this.percentage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    //TODO: Building out a binary of height: small or large depending on region size needs
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: primary,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Stack(
          // mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BodyOne(data, fontSize: 21, color: primaryLighter),
            Center(child: BodyOneWeights('${percentage.toStringAsFixed(0)}%')),
          ],
        ),
      ),
    );
  }
}
