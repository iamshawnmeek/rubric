import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubric/design_system/colors.dart';

class RubricLogo extends StatelessWidget {
  const new({this.width = 295, this.height = 89, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/logo.svg',
      colorFilter: const ColorFilter.mode(primary, BlendMode.srcIn),
      semanticsLabel: 'Rubric',
      width: width,
      height: height,
    );
  }
}
