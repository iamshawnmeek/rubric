import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubric/components/colors.dart';

class SmallLogo extends StatelessWidget {
  const SmallLogo({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SvgPicture.asset(
        'assets/images/logo.svg',
        colorFilter: ColorFilter.mode(primary, BlendMode.srcIn),
        semanticsLabel: 'rubric logo',
        width: 120,
        height: 36,
      ),
    );
  }
}
