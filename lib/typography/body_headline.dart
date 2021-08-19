import 'package:flutter/material.dart';

class BodyHeadline extends StatelessWidget {
  const BodyHeadline(
    this.data, {
    this.fontSize = 36,
    this.color = Colors.white,
    Key? key,
  }) : super(key: key);

  final String data;
  final double fontSize;
  final Color color;

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
