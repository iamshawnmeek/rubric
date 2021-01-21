import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/typography/headline_one.dart';
import 'components/small_logo.dart';
// import 'package:dotted_line/dotted_line.dart';
import 'package:dotted_border/dotted_border.dart';

class AssignGroupsLanding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 36),
                    SmallLogo(),
                    SizedBox(height: 60),
                    HeadlineOne('Assign Groups'),
                    SizedBox(height: 46),
                    DottedBorder(
                      borderType: BorderType.RRect,
                      dashPattern: [4, 4, 4, 4],
                      color: lightgray,
                      radius: Radius.circular(12),
                      child: Container(
                          height: 185, // should this be fractional height?
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                          )),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FractionallySizedBox(
                //fractions out the container
                heightFactor:
                    .45, //changed from .50 to help add some white space
                child: Container(
                  width:
                      400, //how to make width 100% or stretch edges w/o numerical value?
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 18.0, horizontal: 22),
                    child: FaIcon(
                      FontAwesomeIcons.chevronLeft,
                      color: primaryLightest,
                    ),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: primaryDark,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
