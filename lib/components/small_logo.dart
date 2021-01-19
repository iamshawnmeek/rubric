import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubric/components/colors.dart';

Widget smallLogo() {
  return Align(
    alignment: Alignment.centerLeft,
    child: SvgPicture.asset(
      'assets/images/logo.svg',
      color: primary,
      semanticsLabel: 'rubric logo',
      width: 120,
      height: 36,
    ),
  );
}
