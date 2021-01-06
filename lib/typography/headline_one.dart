import 'package:flutter/material.dart';

class HeadlineOne extends StatelessWidget {
  final String data;
  final double fontSize;

  const HeadlineOne(
    this.data, {
    this.fontSize = 36,
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
