import 'package:flutter/material.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/design_system/spacing.dart';
import 'package:rubric/design_system/typography/card_next.dart';
import 'package:rubric/l10n/l10n.dart';

/// The orange call-to-action pill that docks at the bottom of a step.
///
/// [widthFactor] is the share of the screen width the side padding takes on
/// each side — .25 for "Next", .225 for the longer "Set Grading Scale".
class AccentButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onTap,
    this.widthFactor = .25,
    this.enabled = true,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final double widthFactor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final active = enabled && onTap != null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * widthFactor),
      child: Semantics(
        button: true,
        enabled: active,
        label: label,
        onTap: active ? onTap : null,
        excludeSemantics: true,
        // Disabled is drawn in palette colors, not by fading the orange: a
        // translucent accent over purple reads as muddy brown (seen on device).
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          child: Material(
            color: active ? accent : primaryDark,
            borderRadius: Corners.card,
            child: InkWell(
              borderRadius: Corners.card,
              onTap: active ? onTap : null,
              child: SizedBox(
                height: Sizes.ctaHeight,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FittedBox(
                      child: CardNext(label, color: active ? null : inactive),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NextButton extends StatelessWidget {
  const new({required this.onTap, this.label, super.key});

  final VoidCallback? onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return AccentButton(label: label ?? context.l10n.nextTitle, onTap: onTap);
  }
}
