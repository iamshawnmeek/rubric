import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/design_system/spacing.dart';
import 'package:rubric/design_system/typography/body_placeholder.dart';

/// The dashed outline used for drop zones and "add another" affordances.
class DashedBox extends StatelessWidget {
  const new({
    required this.label,
    this.height = 85,
    this.highlighted = false,
    this.onTap,
    super.key,
  });

  final String label;
  final double height;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? accent : lightGray;
    return Semantics(
      button: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: DottedBorder(
          options: RoundedRectDottedBorderOptions(
            dashPattern: const [4, 4],
            color: color,
            radius: Corners.dropTarget,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: height,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: Corners.card,
              color: highlighted ? primaryDark.withValues(alpha: .4) : null,
            ),
            child: Center(child: BodyPlaceholder(label, color: color)),
          ),
        ),
      ),
    );
  }
}

/// A [DashedBox] that accepts dragged [T]s and lights up while one hovers.
class DashedDropTarget<T extends Object> extends StatelessWidget {
  const new({
    required this.label,
    required this.onAccept,
    this.canAccept,
    super.key,
  });

  final String label;
  final void Function(T value) onAccept;
  final bool Function(T value)? canAccept;

  @override
  Widget build(BuildContext context) {
    return DragTarget<T>(
      onWillAcceptWithDetails: (d) => canAccept?.call(d.data) ?? true,
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidates, _) =>
          DashedBox(label: label, highlighted: candidates.isNotEmpty),
    );
  }
}
