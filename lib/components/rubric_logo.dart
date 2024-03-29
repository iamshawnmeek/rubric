import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubric/components/colors.dart';

class RubricLogo extends StatelessWidget {
  const RubricLogo({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/logo.svg',
      colorFilter: ColorFilter.mode(primary, BlendMode.srcIn),
      semanticsLabel: 'rubric logo',
      width: 295,
      height: 89,
    );
  }
}
