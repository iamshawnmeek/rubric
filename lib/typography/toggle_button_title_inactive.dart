import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';

class ToggleButtonTitleInactive extends StatelessWidget {
  const ToggleButtonTitleInactive(
    this.data, {
    Key? key,
    this.fontSize = 21,
    this.color = inactive,
  }) : super(key: key);

  final String data;
  final double fontSize;
  final Color color;

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
