import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/rubric_card.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:rubric/typography/headline_one.dart';
import 'components/small_logo.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:rubric/iterable_extensions.dart';
import 'package:rubric/list_extensions.dart';

class AssignGroupsLanding extends ConsumerWidget {
  @override
  Widget build(BuildContext context, ScopedReader watch) {
    final rubric = watch(rubricProviderRef.state);

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
                heightFactor: .45,
                child: Container(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 52,
                          width: 44,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FaIcon(
                              FontAwesomeIcons.chevronLeft,
                              color: primaryLightest,
                            ),
                          ),
                        ),
                        SizedBox(height: 24),
                        ..._buildObjectives(rubric),
                      ],
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
