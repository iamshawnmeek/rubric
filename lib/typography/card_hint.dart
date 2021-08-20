import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';

class CardHint extends StatelessWidget {
  const CardHint(
    this.data, {
    Key? key,
    this.fontSize = 18,
  }) : super(key: key);

  final String data;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: TextStyle(
        color: primaryLight,
        fontFamily: 'Avenir-Black',
        fontSize: fontSize,
      ),
    );
  }
}
