import 'package:flutter/material.dart';

import 'package:rubric/typography/body_placeholder.dart';

class RubricTextField extends StatefulWidget {
  final void Function(String)? onEditingComplete;
  final void Function(String p1)? onChanged;
  final String hintText;
  final int maxLines;

  const RubricTextField({
    required this.hintText,
    this.onEditingComplete,
    this.onChanged,
    this.maxLines = 1,
    Key? key,
  }) : super(key: key);

  @override
  _RubricTextFieldState createState() => _RubricTextFieldState();
}

class _RubricTextFieldState extends State<RubricTextField> {
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onEditingComplete: () => widget.onEditingComplete?.call(controller.text),
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
      style: BodyPlaceholder.textStyle.copyWith(color: Colors.white),
      decoration: InputDecoration.collapsed(
        hintText: widget.hintText,
        hintStyle: BodyPlaceholder.textStyle,
      ).copyWith(hintMaxLines: 3),
      keyboardAppearance: Brightness.dark, //iOS only
    );
  }
}
