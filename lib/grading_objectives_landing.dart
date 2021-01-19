import 'package:flow_builder/flow_builder.dart';
import 'package:flutter/material.dart';
import 'package:rubric/components/create_card.dart';
import 'package:rubric/components/next_button.dart';
import 'package:rubric/components/rubric_card.dart';
import 'package:rubric/components/small_logo.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/enums.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:rubric/typography/headline_one.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/iterable_extensions.dart';
import 'package:rubric/list_extensions.dart';

class GradingObjectivesLanding extends ConsumerWidget {
  final FlowController flowController;

  GradingObjectivesLanding({@required this.flowController});

  @override
  Widget build(BuildContext context, ScopedReader watch) {
    final rubric = watch(rubricProviderRef.state);

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
                HeadlineOne('Grading Objectives'),
                SizedBox(height: 46),
                ..._buildObjectives(rubric),
                SizedBox(height: 16),
                CreateCard(),
                SizedBox(height: 90),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: NextButton(
        onTap: () {
          flowController.update((_) => OnboardingFlow.assignGroups);
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  List<Widget> _buildObjectives(Rubric rubric) {
    return rubric.objectives
        .mapWithIndex(
          (i, objective) => RubricCard(
            cardHintText: 'Objective ${i + 1}',
            cardTitleText: objective.title,
          ),
        )
        .joinWith(SizedBox(height: 16));
  }
}
