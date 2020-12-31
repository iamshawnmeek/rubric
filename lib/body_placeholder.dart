import 'package:flutter/material.dart';
import 'package:rubric/colors.dart';

class BodyPlaceholder extends StatelessWidget {
  static TextStyle textStyle = TextStyle(
    color: primaryLighter,
    fontFamily: 'Avenir-Heavy',
    fontSize: 24,
    height: 1.2,
  );
  final String data;

  const BodyPlaceholder(this.data);

  @override
  Widget build(BuildContext context) {
    return Text(data, style: textStyle);
  }
}
