import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubric/colors.dart';
import 'package:rubric/typography/headline_one.dart';

class GradingObjectivesLanding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 36),
              smallLogo(),
              SizedBox(height: 60),
              HeadlineOne('Grading Objectives'),
              SizedBox(height: 46),
              Container(
                height: 85,
                decoration: BoxDecoration(
                  color: primaryCard,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget smallLogo() {
    return SvgPicture.asset(
      'assets/images/logo.svg',
      color: primary,
      semanticsLabel: 'rubric logo',
      width: 120,
      height: 36,
    );
  }
}
