import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';

class BodyGradingScaleInput extends StatelessWidget {
  final String data;
  final double fontSize;
  final Color color;

  const BodyGradingScaleInput(
    this.data, {
    this.fontSize = 21,
    this.color = primaryLighter,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: TextStyle(
        fontFamily: 'Avenir-Heavy',
        fontSize: fontSize,
        height: 1.2,
        color: color,
      ),
    );
  }
}
