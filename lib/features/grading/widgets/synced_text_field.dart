import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rubric/design_system/design_system.dart';

/// A [RubricTextField] bound to a value that can also change from outside
/// (undo, switching student, inserting a snippet). External changes replace
/// the text; the teacher's own keystrokes are never echoed back over it.
class SyncedTextField extends StatefulWidget {
  const new({
    required this.value,
    required this.onChanged,
    required this.hintText,
    this.style,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.semanticLabel,
    this.textCapitalization = TextCapitalization.sentences,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String hintText;
  final TextStyle? style;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final String? semanticLabel;
  final TextCapitalization textCapitalization;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller;

  /// The last value this field reported or accepted. Set in initState, NOT
  /// as a lazy `late` initialiser: that would first run inside
  /// didUpdateWidget, already holding the new value, and swallow it.
  late String _emitted;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _emitted = widget.value;
  }

  @override
  void didUpdateWidget(SyncedTextField old) {
    super.didUpdateWidget(old);
    if (widget.value != _emitted && widget.value != _controller.text) {
      _emitted = widget.value;
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RubricTextField(
      controller: _controller,
      hintText: widget.hintText,
      style: widget.style,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textInputAction: widget.textInputAction,
      semanticLabel: widget.semanticLabel,
      textCapitalization: widget.textCapitalization,
      onChanged: (text) {
        _emitted = text;
        widget.onChanged(text);
      },
    );
  }
}
