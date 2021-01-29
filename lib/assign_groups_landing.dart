import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/rubric_card.dart';
import 'package:rubric/components/rubric_text_field.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:rubric/typography/body_placeholder.dart';
import 'package:rubric/typography/headline_one.dart';
import 'components/small_logo.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:rubric/iterable_extensions.dart';
import 'package:rubric/list_extensions.dart';

class AssignGroupsLanding extends ConsumerWidget {
  @override
  Widget build(BuildContext contextInstance, ScopedReader watch) {
    final rubricInstance = watch(rubricProviderRef.state);

    return GestureDetector(
      onTap: () => FocusScope.of(contextInstance).unfocus(),
      child: Scaffold(
        body: Stack(
          children: [
            SingleChildScrollView(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24), //adjust this globally to 24
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 36),
                      SmallLogo(),
                      SizedBox(height: 60),
                      HeadlineOne('Assign Groups'),
                      SizedBox(height: 46),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RubricTextField(
                              onChanged: (_) {}, hintText: 'Group 1'),
                          SizedBox(height: 24),
                          _firstDragTarget(),
                        ],
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
                      padding: const EdgeInsets.all(24),
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
                          ..._buildObjectives(
                              rubric: rubricInstance, context: contextInstance),
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
      ),
    );
  }

  DottedBorder _firstDragTarget() {
    return DottedBorder(
      borderType: BorderType.RRect,
      dashPattern: [4, 4, 4, 4],
      color: lightGray,
      radius: Radius.circular(12),
      child: Container(
        height: 85,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: BodyPlaceholder(
            'Drag objective here',
            color: lightGray,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildObjectives({Rubric rubric, BuildContext context}) {
    final deviceWidth = MediaQuery.of(context).size.width;

    return rubric.objectives
        .mapWithIndex(
          (i, objective) => Draggable(
            data: 'Objective ${i + 1}',
            feedback: Container(
              width: deviceWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Material(
                  color: Colors.transparent,
                  child: RubricCard(
                    cardHintText: 'Objective ${i + 1}',
                    cardTitleText: objective.title,
                  ),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: .4,
              child: RubricCard(
                cardHintText: 'Objective ${i + 1}',
                cardTitleText: objective.title,
              ),
            ),
            child: RubricCard(
              cardHintText: 'Objective ${i + 1}',
              cardTitleText: objective.title,
            ),
          ),
        )
        .joinWith(SizedBox(height: 16));
  }
}
