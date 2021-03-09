import 'package:flutter/material.dart';

import 'package:rubric/components/colors.dart';
import 'package:rubric/typography/body_one.dart';
import 'package:rubric/typography/headline_one.dart';

class AssignWeights extends StatelessWidget {
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
                    // study layout builder this later
                    builder: (context, constraints) {
                      final height =
                          constraints.maxHeight; //dynamic to user screen height

                      return Container(
                        child: Column(
                          children: [
                            WeightSlider(data: 'Process: 33%'),
                            WeightSlider(data: 'Realization: 33%'),
                            WeightSlider(data: 'Experimentation: 33%')
                          ],
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
}

class WeightSlider extends StatelessWidget {
  final String data;

  const WeightSlider({
    @required
        this.data, //study: constructor argument, populating value on ln 56
    Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BodyOne(data, fontSize: 24);
  }
}
