import 'package:flutter/material.dart';
import 'package:rubric/typography/headline_one.dart';
import 'components/small_logo.dart';

class AssignGroupsLanding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
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
    );
  }
}
