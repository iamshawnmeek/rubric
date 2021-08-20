import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';

class CardNext extends StatelessWidget {
  const CardNext(
    this.data, {
    this.fontSize = 20,
    Key? key,
  }) : super(key: key);

  final String data;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: TextStyle(
        color: secondary,
        fontFamily: 'Avenir-Black',
        fontSize: fontSize,
      ),
    );
  }
}
