import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class RubricLock extends StatelessWidget {
  final VoidCallback onTap;
  final bool isActive;

  RubricLock({
    required this.onTap,
    required this.isActive,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      //allows padding to be hit as well as icon
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11.5),
        child: isActive ? buildActiveLock() : buildDefaultLock(),
      ),
    );
  }

  Widget buildDefaultLock() {
    return SvgPicture.asset(
      'assets/images/icon-lock-default.svg',
      semanticsLabel: 'rubric lock default',
      width: 16,
      height: 21,
    );
  }

  Widget buildActiveLock() {
    return SvgPicture.asset(
      'assets/images/icon-lock-locked.svg',
      semanticsLabel: 'rubric lock locked',
      width: 16,
      height: 20,
    );
  }
}
