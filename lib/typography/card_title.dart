import 'package:flutter/material.dart';

class CardTitle extends StatelessWidget {
  final String data;
  final double fontSize;

  const CardTitle(
    this.data, {
    this.fontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: TextStyle(
        color: Colors.white,
        fontFamily: 'Avenir-Black',
        fontSize: fontSize,
      ),
    );
  }
}
