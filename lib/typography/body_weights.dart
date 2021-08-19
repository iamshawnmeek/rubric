import 'package:flutter/material.dart';

class BodyOneWeights extends StatelessWidget {
  const BodyOneWeights(
    this.data, {
    this.fontSize = 48,
    Key? key,
  }) : super(key: key);

  final String data;
  final double fontSize;

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
