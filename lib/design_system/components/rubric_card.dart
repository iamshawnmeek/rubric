import 'package:flutter/material.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/design_system/spacing.dart';
import 'package:rubric/design_system/typography/card_hint.dart';
import 'package:rubric/design_system/typography/card_title.dart';

/// The signature card: a small purple hint above a bold white title.
///
/// Tappable when [onTap] is supplied; [trailing] sits to the right of the text
/// (a chevron, a score, a menu).
class RubricCard extends StatelessWidget {
  const new({
    required this.cardHintText,
    required this.cardTitleText,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.footer,
    this.color = primaryCard,
    this.titleMaxLines,
    super.key,
  });

  final String cardHintText;
  final String cardTitleText;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Widget? footer;
  final Color color;
  final int? titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cardHintText.isNotEmpty) ...[
          CardHint(cardHintText),
          const SizedBox(height: Insets.xs),
        ],
        CardTitle(
          cardTitleText,
          maxLines: titleMaxLines,
          overflow: titleMaxLines == null ? null : TextOverflow.ellipsis,
        ),
        if (footer != null) ...[const SizedBox(height: Insets.sm), footer!],
      ],
    );

    return Semantics(
      button: onTap != null,
      label: '$cardHintText, $cardTitleText',
      excludeSemantics: true,
      child: Material(
        color: color,
        borderRadius: Corners.card,
        child: InkWell(
          borderRadius: Corners.card,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: Insets.card,
            child: trailing == null
                ? content
                : Row(
                    children: [
                      Expanded(child: content),
                      const SizedBox(width: Insets.sm),
                      trailing!,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
