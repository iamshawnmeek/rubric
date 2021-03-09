import 'package:flutter/material.dart' hide Slider;

import 'package:rubric/components/colors.dart';
import 'package:rubric/domain/weight/rubric_region.dart';
import 'package:rubric/domain/weight/slider.dart';
import 'package:rubric/presentation/regions/region_view_model.dart';
import 'package:rubric/typography/body_one.dart';
import 'package:rubric/typography/headline_one.dart';

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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final height = constraints.maxHeight;

                      return Container(
                        child: Column(
                          children: model.mapController(
                            sliderBuilder: _buildSlider,
                            regionBuilder: _buildRegion,
                          ),
                        ),
                        decoration: BoxDecoration(
                          color: primaryCard,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegion(RubricRegion region) {
    // TODO: get the height of the region area and divide by the region weight
    return WeightSlider(data: region.title, height: region.weight);
  }

  Widget _buildSlider(Slider slider) {
    return Container(
      height: 4,
      color: Colors.white,
    );
  }
}

class WeightSlider extends StatelessWidget {
  final String data;
  final double height;

  const WeightSlider({
    Key key,
    @required this.data,
    @required this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      child: Center(child: BodyOne(data, fontSize: 24)),
    );
  }
}
