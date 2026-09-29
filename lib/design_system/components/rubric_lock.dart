import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The padlock toggle used on weight regions.
class RubricLock extends StatelessWidget {
  const new({required this.onTap, required this.isActive, super.key});

  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: isActive,
      label: isActive ? 'Unlock weight' : 'Lock weight',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        // allows padding to be hit as well as icon
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11.5),
          child: isActive
              ? SvgPicture.asset(
                  'assets/images/icon-lock-locked.svg',
                  width: 16,
                  height: 20,
                )
              : SvgPicture.asset(
                  'assets/images/icon-lock-default.svg',
                  width: 16,
                  height: 21,
                ),
        ),
      ),
    );
  }
}
