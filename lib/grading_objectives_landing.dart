import 'package:flutter/material.dart';

import 'package:flow_builder/flow_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rubric/components/create_card.dart';
import 'package:rubric/components/next_button.dart';
import 'package:rubric/components/rubric_card.dart';
import 'package:rubric/components/small_logo.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/enums.dart';
import 'package:rubric/hooks/scroll_hook.dart';
import 'package:rubric/iterable_extensions.dart';
import 'package:rubric/list_extensions.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:rubric/typography/headline_one.dart';

class GradingObjectivesLanding extends StatefulWidget {
  final FlowController flowController;

  GradingObjectivesLanding({@required this.flowController});

  @override
  _GradingObjectivesLandingState createState() =>
      _GradingObjectivesLandingState();
}

class _GradingObjectivesLandingState extends State<GradingObjectivesLanding> {
  ScrollHookState scrollHook;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, watch, _) {
        final rubric = watch(rubricProviderRef.state);
        final shouldShowNextButton = rubric.objectives.length >= 2;

        return Scaffold(
          body: ScrollHook(
            builder: (context, scrollController, scrollHook) {
              this.scrollHook = scrollHook;

              return SingleChildScrollView(
                controller: scrollController,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
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
              );
            },
          ),
          // Ternary Operator: basically an if/else statement
          floatingActionButton: shouldShowNextButton
              ? NextButton(onTap: () {
                  widget.flowController.update(
                    (_) => OnboardingFlow.assignGroups,
                  );
                })
              : null,
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
        );
      },
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
