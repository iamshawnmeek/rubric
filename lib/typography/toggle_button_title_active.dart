import 'package:flutter/material.dart';

class ToggleButtonTitleActive extends StatelessWidget {
  final String data;
  final double fontSize;
  final Color color;

  const ToggleButtonTitleActive(
    this.data, {
    this.fontSize = 21,
    this.color = Colors.white,
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
