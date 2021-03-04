import 'package:flutter/material.dart';

import 'package:rubric/components/colors.dart';

class CardHint extends StatelessWidget {
  final String data;
  final double fontSize;

  const CardHint(
    this.data, {
    this.fontSize = 18,
  });

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
