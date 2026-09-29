import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/design_system/spacing.dart';

/// The translucent "+" card that ends a list of cards and adds another.
class CreateCard extends StatelessWidget {
  const new({required this.onPressed, this.label, super.key});

  final VoidCallback onPressed;

  /// Accessibility label; the card itself shows only the plus glyph.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label ?? 'Add',
      onTap: onPressed,
      excludeSemantics: true,
      child: Opacity(
        opacity: .5,
        child: Material(
          color: primaryCard,
          borderRadius: Corners.card,
          child: InkWell(
            borderRadius: Corners.card,
            onTap: onPressed,
            child: const SizedBox(
              height: 92,
              child: Center(child: FaIcon(FontAwesomeIcons.plus, color: white)),
            ),
          ),
        ),
      ),
    );
  }
}
