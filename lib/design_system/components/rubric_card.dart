import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
    this.semanticValue,
    this.customSemanticsActions,
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

  /// Announced after the label (e.g. "12 of 24 graded").
  final String? semanticValue;

  /// Extra screen-reader actions (e.g. "Actions for Biology").
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;

  @override
  Widget build(BuildContext context) {
    // The hint + title are announced as ONE label on the card's own node, which
    // carries the tap/long-press actions. Only the text is excluded: an
    // interactive trailing widget or footer must stay reachable on its own.
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Column(
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
            ],
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: Insets.sm),
          Semantics(container: true, child: footer),
        ],
      ],
    );

    return Semantics(
      container: true,
      button: onTap != null,
      label: [
        cardHintText,
        cardTitleText,
      ].where((s) => s.isNotEmpty).join(', '),
      value: semanticValue,
      onTap: onTap,
      onLongPress: onLongPress,
      customSemanticsActions: customSemanticsActions,
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
                      Semantics(container: true, child: trailing),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
