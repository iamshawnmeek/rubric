import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
// import 'package:rubric/components/colors.dart';

class RubricLock extends StatefulWidget {
  const RubricLock({
    Key key,
  }) : super(key: key);

  @override
  _RubricLockState createState() => _RubricLockState();
}

class _RubricLockState extends State<RubricLock> {
  bool isTapped = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior:
          HitTestBehavior.opaque, //allows padding to be hit as well as icon
      onTap: () {
        setState(() {
          isTapped =
              !isTapped; //see how this aligns with line 15 and also line 25 logic
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11.5),
        child: isTapped ? buildActiveLock() : buildDefaultLock(),
      ),
    );
  }

  Widget buildDefaultLock() {
    return SvgPicture.asset(
      'assets/images/icon-lock-default.svg',
      // color: primary,
      semanticsLabel: 'rubric lock default',
      width: 16,
      height: 21,
    );
  }

  Widget buildActiveLock() {
    return SvgPicture.asset(
      'assets/images/icon-lock-locked.svg',
      // color: primary,
      semanticsLabel: 'rubric lock locked',
      width: 16,
      height: 20,
    );
  }
}
