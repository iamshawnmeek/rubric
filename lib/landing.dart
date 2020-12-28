import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubric/colors.dart';

class Landing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              child: SvgPicture.asset(
                'assets/images/logo.svg',
                color: primary,
                semanticsLabel: 'rubric logo',
                width: 295,
                height: 89,
              ),
            ),
            SizedBox(height: 300), //is this the best way to do this?
          ],
        ),
      ),
    );
  }
}
