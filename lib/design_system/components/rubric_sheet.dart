import 'package:flutter/material.dart';
import 'package:harbor/harbor.dart';
import 'package:rubric/design_system/colors.dart';
import 'package:rubric/design_system/spacing.dart';
import 'package:rubric/design_system/typography/headline_one.dart';

/// Shows [child] in the floating dark-purple sheet the original "Add an
/// Objective" flow used: inset 12pt from the edges, rounded, keyboard-aware.
Future<T?> showRubricSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .4),
    // Clear of the keyboard AND the home indicator, plus our 12pt float.
    // It used to add the keyboard by hand and nothing else, so with the
    // keyboard down the sheet sat 12pt over the home indicator.
    builder: (context) => HarborMoored(
      edges: const {HarborEdge.bottom},
      extra: const EdgeInsetsDirectional.only(bottom: Insets.sm),
      child: child,
    ),
  );
}

/// The sheet surface itself, with an optional [title] in HeadlineOne.
class RubricSheet extends StatelessWidget {
  const new({
    required this.child,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(24, 36, 24, 36),
    super.key,
  });

  final String? title;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
      child: ClipRRect(
        borderRadius: Corners.card,
        child: Material(
          color: primaryDark,
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  HeadlineOne(title!, fontSize: 30),
                  const SizedBox(height: Insets.lg),
                ],
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The primary-purple well that holds a large text field inside a sheet.
class RubricFormWell extends StatelessWidget {
  const new({required this.child, this.minHeight = 0, super.key});

  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(borderRadius: Corners.card, color: primary),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: child,
    );
  }
}
