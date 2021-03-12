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
                      final height = constraints.maxHeight; //here

                      return Container(
                        child: Column(
                          children: model.mapController(
                            sliderBuilder: _buildSlider,
                            regionBuilder:
                                _buildRegion(height), //want dynamic height for
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

  Widget Function(RubricRegion) _buildRegion(double height) {
    return (RubricRegion region) {
      final regionHeight = height * (region.weight / 100);
      final percentage = region.weight.roundToDouble();

      return WeightSlider(
        data: region.title,
        height: regionHeight - 1,
        percentage: percentage,
      );
    };
  }

  Widget _buildSlider(Slider slider) {
    return Container(
      height: 1, //interesting, since this is part of the overall region
      color: Colors.white,
    );
  }
}

class WeightSlider extends StatelessWidget {
  final String data;
  final double height;
  final double percentage;

  const WeightSlider({
    Key key,
    @required this.data,
    @required this.height,
    @required this.percentage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BodyOne(data, fontSize: 24),
          BodyOne(': ${percentage.toStringAsFixed(0)}%'),
        ],
      ),
    );
  }
}
