import 'package:flutter/material.dart';

class BodyOne extends StatelessWidget {
  final String data;
  final double fontSize;

  const BodyOne(
    this.data, {
    this.fontSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: TextStyle(
        color: Colors.white,
        fontFamily: 'Avenir-Heavy',
        fontSize: fontSize,
        height: 1.3,
      ),
    );
  }
}
