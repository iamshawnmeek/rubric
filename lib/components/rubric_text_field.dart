import 'package:flutter/material.dart';

import 'package:rubric/typography/body_placeholder.dart';

class RubricTextField extends StatelessWidget {
  final void Function(String p1) onChanged;
  final String hintText;
  final int maxLines;

  const RubricTextField({
    Key key,
    @required this.onChanged,
    @required this.hintText,
    this.maxLines = 1,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextField(
      maxLines: maxLines,
      onChanged: onChanged,
      style: BodyPlaceholder.textStyle.copyWith(color: Colors.white),
      decoration: InputDecoration.collapsed(
        hintText: hintText,
        hintStyle: BodyPlaceholder.textStyle,
      ).copyWith(hintMaxLines: 3),
      keyboardAppearance: Brightness.dark, //iOS only
    );
  }
}
