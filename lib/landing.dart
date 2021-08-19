import 'package:flutter/material.dart';
import 'package:flow_builder/flow_builder.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/rubric_logo.dart';
import 'package:rubric/onboarding_bottom_sheet.dart';

class Landing extends StatelessWidget {
  final FlowController flowController;

  Landing({Key? key, required this.flowController}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.all(36),
        child: FloatingActionButton(
          foregroundColor: primaryDark,
          backgroundColor: accent,
          onPressed: () {
            showModalBottomSheet(
              isScrollControlled: true,
              context: context,
              builder: (context) => OnboardingBottomSheet(
                flowController: flowController,
              ),
            );
          },
          child: Icon(Icons.add),
        ),
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: height * .3), //MQ Use
            RubricLogo(),
          ],
        ),
      ),
    );
  }
}
