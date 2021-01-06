import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/onboard.dart';

class Landing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height; //MQ Wow

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        foregroundColor: primaryDark,
        backgroundColor: accent,
        child: Icon(Icons.add),
        onPressed: () {
          showModalBottomSheet(
            isScrollControlled: true,
            context: context,
            builder: (context) => Onboard(),
          );
        },
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: height * .3), //MQ Use
            SvgPicture.asset(
              'assets/images/logo.svg',
              color: primary,
              semanticsLabel: 'rubric logo',
              width: 295,
              height: 89,
            ),
          ],
        ),
      ),
    );
  }
}
