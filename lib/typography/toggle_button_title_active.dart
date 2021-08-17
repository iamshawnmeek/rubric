import 'package:flutter/material.dart';

class ToggleButtonTitleActive extends StatelessWidget {
  const ToggleButtonTitleActive(
    this.data, {
    this.fontSize = 21,
    Key? key,
  }) : super(key: key);

  final String data;
  final double fontSize;

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
