import 'package:flutter/material.dart';

import 'package:rubric/components/colors.dart';

class BodyPlaceholder extends StatelessWidget {
  static TextStyle textStyle = TextStyle(
    color: primaryLighter,
    fontFamily: 'Avenir-Heavy',
    fontSize: 24,
    height: 1.2,
  );

  final String data;
  final Color color;

  const BodyPlaceholder(this.data, {this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      overflow: TextOverflow.ellipsis,
      style: textStyle.copyWith(
        color: color ?? textStyle.color,
      ),
    );
  }
}
