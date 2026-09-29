import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';

/// Content never stretches wider than this on tablets.
const double builderMaxWidth = 720;

/// `90` for whole numbers, `89.9` otherwise.
String formatNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// Allows digits and a single decimal point.
final decimalInput = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
];

/// A [RubricTextField] bound to a draft value.
///
/// Edits flow out through [onChanged]; the field only takes [value] back when
/// it changes from somewhere else (a preset, an undo), so typing is never
/// interrupted by the draft echoing a normalised copy of the text.
class DraftField extends StatefulWidget {
  const new({
    required this.value,
    required this.onChanged,
    required this.hintText,
    this.style,
    this.hintStyle,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.focusNode,
    this.semanticLabel,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.sentences,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String hintText;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final bool autofocus;
  final TextCapitalization textCapitalization;

  @override
  State<DraftField> createState() => _DraftFieldState();
}

class _DraftFieldState extends State<DraftField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(DraftField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _controller.text) {
      _controller.text = widget.value;
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
      onChanged: widget.onChanged,
      style: widget.style,
      hintStyle: widget.hintStyle,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textInputAction: widget.textInputAction,
      focusNode: widget.focusNode,
      semanticLabel: widget.semanticLabel,
      autofocus: widget.autofocus,
      textCapitalization: widget.textCapitalization,
    );
  }
}

/// A primary-purple box holding a compact field (grade letters, minimums,
/// level points).
class FieldBox extends StatelessWidget {
  const new({required this.child, this.width, super.key});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: Sizes.minTap + 8),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
      decoration: BoxDecoration(color: primary, borderRadius: Corners.card),
      child: child,
    );
  }
}

/// Explanatory copy under a step title.
class StepIntro extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: Text(text, style: RubricTextStyles.bodySmall),
    );
  }
}

/// A problem the teacher needs to fix, marked with an icon as well as color.
class ProblemNote extends StatelessWidget {
  const new(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: FaIcon(
              FontAwesomeIcons.circleExclamation,
              color: accent,
              size: 16,
            ),
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Text(
              message,
              style: RubricTextStyles.bodySmall.copyWith(color: white),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 48pt round icon button in palette colors.
class BuilderIconButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = primaryLighter,
    super.key,
  });

  final FaIconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      constraints: const BoxConstraints(
        minWidth: Sizes.minTap,
        minHeight: Sizes.minTap,
      ),
      icon: FaIcon(icon, color: color, size: 18),
    );
  }
}

/// One row of a choice sheet; tapping it pops the sheet with [value].
class SheetOption<T> extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final FaIconData icon;
  final String label;
  final T value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: Corners.card,
      onTap: () => Navigator.of(context).pop(value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            FaIcon(icon, color: primaryLighter, size: 18),
            const SizedBox(width: Insets.md),
            Expanded(child: Text(label, style: RubricTextStyles.listTitle)),
          ],
        ),
      ),
    );
  }
}
