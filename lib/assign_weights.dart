import 'package:flow_builder/flow_builder.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/enums.dart';

class AssignWeights extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    FlowController<OnboardingFlow> flowController;
    return GestureDetector(
      child: Scaffold(
        body: SingleChildScrollView(
          child: SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0), //placeholder
              child: _buildBackChevron(flowController),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackChevron(FlowController<OnboardingFlow> flowController) {
    return SizedBox(
      height: 52,
      width: 44,
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => flowController.update(
            (_) => OnboardingFlow.assignGroups, //WIP: How to go back?
          ),
          child: FaIcon(
            FontAwesomeIcons.chevronLeft,
            color: primaryLightest,
          ),
        ),
      ),
    );
  }
}
