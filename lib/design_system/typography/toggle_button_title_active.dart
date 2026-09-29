import 'package:flutter/widgets.dart';
import 'package:rubric/design_system/typography/text_styles.dart';

class ToggleButtonTitleActive extends StatelessWidget {
  const new(
    this.data, {
    this.fontSize,
    this.color,
    this.maxLines,
    this.overflow,
    this.textAlign,
    super.key,
  });

  final String data;
  final double? fontSize;
  final Color? color;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: RubricTextStyles.toggleActive.copyWith(
        fontSize: fontSize,
        color: color,
      ),
    );
  }
}
