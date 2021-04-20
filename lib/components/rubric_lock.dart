import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
// import 'package:rubric/components/colors.dart';

class RubricLock extends StatelessWidget {
  const RubricLock({
    Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        print('I have been tapped!');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11.5),
        child: SvgPicture.asset(
          'assets/images/icon-lock-default.svg',
          // color: primary,
          semanticsLabel: 'rubric lock default',
          width: 16,
          height: 21,
        ),
      ),
    );
  }
}
