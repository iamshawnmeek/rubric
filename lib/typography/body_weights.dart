import 'package:flutter/material.dart';

class BodyOneWeights extends StatelessWidget {
  final String data;
  final double fontSize;

  const BodyOneWeights(
    this.data, {
    this.fontSize = 48,
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
