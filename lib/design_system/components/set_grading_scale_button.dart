import 'package:flutter/material.dart';
import 'package:rubric/design_system/components/next_button.dart';
import 'package:rubric/l10n/l10n.dart';

class SetGradingScaleButton extends StatelessWidget {
  const new({required this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AccentButton(
      label: context.l10n.setGradingScaleTitle,
      onTap: onTap,
      widthFactor: .225,
    );
  }
}
