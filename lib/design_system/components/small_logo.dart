import 'package:flutter/material.dart';
import 'package:rubric/design_system/components/rubric_logo.dart';

class SmallLogo extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: RubricLogo(width: 120, height: 36),
    );
  }
}
