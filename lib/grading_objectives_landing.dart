import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/create_card.dart';
import 'package:rubric/components/next_button.dart';
import 'package:rubric/components/rubric_card.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:rubric/typography/headline_one.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/iterable_extensions.dart';
import 'package:rubric/list_extensions.dart';
// import 'package:rubric/typography/card_next.dart';

class GradingObjectivesLanding extends ConsumerWidget {
  @override
  Widget build(BuildContext context, ScopedReader watch) {
    final rubric = watch(rubricProviderRef.state);
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      body: SingleChildScrollView(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 36),
                  smallLogo(),
                  SizedBox(height: 60),
                  HeadlineOne('Grading Objectives'),
                  SizedBox(height: 46),
                  ...rubric.objectives
                      .mapWithIndex(
                        (i, objective) => RubricCard(
                          cardHintText: 'Objective ${i + 1}',
                          cardTitleText: objective.title,
                        ),
                      )
                      .joinWith(SizedBox(height: 16)),
                  SizedBox(height: 16),
                  CreateCard(),
                  SizedBox(height: 16),
                  // Align(
                  //   alignment: Alignment.bottomCenter, //??
                  Positioned(
                    bottom: 0,
                    child: NextBtn(width: width),
                  ),
                  // ),
                ],
              ),
            ),
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
