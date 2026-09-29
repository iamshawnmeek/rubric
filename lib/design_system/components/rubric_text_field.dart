import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/design_system/typography/text_styles.dart';

/// The borderless, large-type text input used throughout the app.
class RubricTextField extends StatefulWidget {
  const new({
    required this.hintText,
    this.initialValue,
    this.onEditingComplete,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines,
    this.style,
    this.hintStyle,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.sentences,
    this.controller,
    this.focusNode,
    this.semanticLabel,
    super.key,
  });

  final String hintText;
  final String? initialValue;
  final void Function(String)? onEditingComplete;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final int? maxLines;
  final int? minLines;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? semanticLabel;

  @override
  State<RubricTextField> createState() => _RubricTextFieldState();
}

class _RubricTextFieldState extends State<RubricTextField> {
  late final TextEditingController _owned = TextEditingController(
    text: widget.initialValue,
  );

  TextEditingController get _controller => widget.controller ?? _owned;

  @override
  void dispose() {
    _owned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? RubricTextStyles.bodyPlaceholder;
    return Semantics(
      textField: true,
      label: widget.semanticLabel ?? widget.hintText,
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onEditingComplete: widget.onEditingComplete == null
            ? null
            : () {
                widget.onEditingComplete!(_controller.text);
                FocusScope.of(context).unfocus();
              },
        onSubmitted: widget.onSubmitted,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        onChanged: widget.onChanged,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        inputFormatters: widget.inputFormatters,
        textCapitalization: widget.textCapitalization,
        cursorColor: accent,
        style: base.copyWith(color: white),
        decoration: InputDecoration.collapsed(
          hintText: widget.hintText,
          hintStyle: widget.hintStyle ?? base,
        ).copyWith(hintMaxLines: 3),
        keyboardAppearance: Brightness.dark, // iOS only
      ),
    );
  }
}
