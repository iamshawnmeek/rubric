import 'package:flutter/material.dart';

class BodyPlaceholderWhite extends StatelessWidget {
  static TextStyle textStyle = TextStyle(
    color: Colors.white,
    fontFamily: 'Avenir-Heavy',
    fontSize: 24,
    height: 1.2,
  );
  final String data;

  const BodyPlaceholderWhite(this.data);

  @override
  Widget build(BuildContext context) {
    return Text(data, style: textStyle);
  }
}
