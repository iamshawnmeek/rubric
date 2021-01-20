import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/typography/headline_one.dart';
import 'components/small_logo.dart';

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
                heightFactor: .5,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: primaryDark,
                  ),
                  height: 480, //to change later
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
