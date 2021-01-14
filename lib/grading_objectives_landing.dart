import 'package:flow_builder/flow_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/create_card.dart';
import 'package:rubric/components/rubric_card.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:rubric/typography/headline_one.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/iterable_extensions.dart';

class GradingObjectivesLanding extends ConsumerWidget {
  final FlowController flowController;

  const GradingObjectivesLanding({@required this.flowController});

  @override
  Widget build(BuildContext context, ScopedReader watch) {
    final rubric = watch(rubricProviderRef.state);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 36),
              smallLogo(),
              SizedBox(height: 60),
              HeadlineOne('Grading Objectives'),
              SizedBox(height: 46),
              ...rubric.objectives
                  .map(
                    (objective) => RubricCard(
                      cardHintText: 'Objective 1',
                      cardTitleText: objective.title,
                    ),
                  )
                  .joinWith(SizedBox(height: 16)),
              SizedBox(height: 16),
              CreateCard(flowController: flowController),
            ],
          ),
        ),
      ),
    );
  }

  Widget smallLogo() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SvgPicture.asset(
        'assets/images/logo.svg',
        color: primary,
        semanticsLabel: 'rubric logo',
        width: 120,
        height: 36,
      ),
    );
  }
}
