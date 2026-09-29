import 'package:flutter/widgets.dart';
import 'package:rubric/design_system/typography/text_styles.dart';

class BodyPlaceholder extends StatelessWidget {
  const new(this.data, {this.color, super.key});

  /// Kept for call sites written before [RubricTextStyles] existed.
  static const TextStyle textStyle = RubricTextStyles.bodyPlaceholder;

  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // The original ignored [color] (it copied textStyle.color back onto itself),
    // so drop-target labels rendered primaryLighter instead of the lightGray the
    // call sites asked for. Honouring it matches the design comps.
    return Text(
      data,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: textStyle.copyWith(color: color),
    );
  }
}
