import 'package:flutter/material.dart';

class BodyOne extends StatelessWidget {
  final String data;
  final double fontSize;
  final Color color;

  const BodyOne(
    this.data, {
    this.fontSize = 28,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: TextStyle(
        fontFamily: 'Avenir-Heavy',
        fontSize: fontSize,
        height: 1.3,
        color: color,
      ),
    );
  }
}
