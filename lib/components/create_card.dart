import 'package:flow_builder/flow_builder.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/create_objective_bottom_sheet.dart';
import 'package:rubric/enums.dart';

class CreateCard extends StatelessWidget {
  final FlowController flowController; //updated 1.13.21

  const CreateCard({Key key, @required this.flowController})
      : super(key: key); //updated 1.13.21

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: .5,
      child: Container(
        onPressed: () {
          showModalBottomSheet(
            isScrollControlled: true,
            context: context,
            builder: (context) => CreateObjectiveBottomSheet(
              onCreatePressed: () => flowController
                  .update((_) => OnboardingFlow.gradingObjectives),
            ),
          );
        },
        height: 92,
        child: Center(
          child: FaIcon(FontAwesomeIcons.plus),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 18,
        ),
        decoration: BoxDecoration(
          color: primaryCard,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
