import 'package:flutter/material.dart';

import 'package:rubric/components/colors.dart';

class CardNext extends StatelessWidget {
  final String data;
  final double fontSize;

  const CardNext(
    this.data, {
    this.fontSize = 20,
  });

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
