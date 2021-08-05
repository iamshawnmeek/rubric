import 'package:flutter/material.dart';

class ToggleButtonTitleActive extends StatelessWidget {
  final String data;
  final double fontSize;

  const ToggleButtonTitleActive(
    this.data, {
    this.fontSize = 21,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: TextStyle(
        fontFamily: 'Avenir-Heavy',
        fontSize: fontSize,
        height: 1.2,
      ),
    );
  }
}
