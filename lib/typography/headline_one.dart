import 'package:flutter/material.dart';

class HeadlineOne extends StatelessWidget {
  const HeadlineOne(
    this.data, {
    Key? key,
    this.fontSize = 36,
  }) : super(key: key); 

  final String data;
  final double fontSize;

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
