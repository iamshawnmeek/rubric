import 'package:flutter/material.dart';

class BodyHeadline extends StatelessWidget {
  final String data;
  final double fontSize;
  final Color color;

  const BodyHeadline(
    this.data, {
    this.fontSize = 36,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: TextStyle(
        fontFamily: 'Avenir-Black',
        fontSize: fontSize,
        height: 1.2,
        color: color,
      ),
    );
  }
}
