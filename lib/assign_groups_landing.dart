import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/next_button.dart';
import 'package:rubric/components/rubric_card.dart';
import 'package:rubric/components/rubric_text_field.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/enums.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:rubric/typography/body_placeholder.dart';
import 'package:rubric/typography/headline_one.dart';
import 'components/small_logo.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:rubric/iterable_extensions.dart';
import 'package:rubric/list_extensions.dart';
import 'package:flow_builder/flow_builder.dart';

class AssignGroupsLanding extends ConsumerWidget {
  @override
  Widget build(BuildContext context, ScopedReader watch) {
    final rubricInstance = watch(rubricProviderRef.state);
    final flowController = context.flow<OnboardingFlow>();
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom != 0;
    final bottomSheetObjectives = _buildBottomSheetObjectives(rubricInstance);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Stack(
          children: [
            SingleChildScrollView(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 36),
                      SmallLogo(),
                      SizedBox(height: 60),
                      HeadlineOne('Assign Groups'),
                      SizedBox(height: 46),
                      if (rubricInstance.groups.isNotEmpty)
                        buildGroups(
                          rubric: rubricInstance,
                          context: context,
                        ),
                      SizedBox(height: 24),
                      _buildDragTarget(
                        context: context,
                        text: rubricInstance.groups.isEmpty
                            ? 'Drag objective here'
                            : 'Add New Group',
                      ),
                      SizedBox(
                        height: bottomSheetObjectives.isEmpty
                            ? 110
                            : (MediaQuery.of(context).size.height * .45) +
                                MediaQuery.of(context).padding.bottom,
                      )
                    ],
                  ),
                ),
              ),
            ),
            if (!isKeyboardVisible)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _buildBottomSheet(
                    flowController: flowController,
                    rubric: rubricInstance,
                    context: context,
                    bottomSheetObjectives: bottomSheetObjectives,
                  ),
                ),
              ),
          ],
        ),
        // Ternary Operator: basically an if/else statement
        floatingActionButton: bottomSheetObjectives.isEmpty
            ? NextButton(onTap: () {
                flowController.update((_) => OnboardingFlow.assignWeights);
              })
            : SizedBox(),

        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      ),
    );
  }

  Widget _buildBottomSheet({
    @required FlowController<OnboardingFlow> flowController,
    @required Rubric rubric,
    @required BuildContext context,
    @required List<Objective> bottomSheetObjectives,
  }) {
    return bottomSheetObjectives.isEmpty
        ? SizedBox()
        : Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .45,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: primaryDark,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBackChevron(flowController),
                    SizedBox(height: 24),
                    ..._buildRubricObjectives(
                      rubricObjectives: rubric.objectives,
                      bottomSheetObjectives: bottomSheetObjectives,
                      context: context,
                    ),
                  ],
                ),
              ),
            ),
          );
  }

  List<Objective> _buildBottomSheetObjectives(Rubric rubric) {
    final objectivesInGroups = rubric.groups
        .map((group) => group.objectives)
        .expand((e) => e)
        .toList();

    final remainingBottomSheetObjectives =
        List<Objective>.from(rubric.objectives)
          ..removeWhere(
            (objective) => objectivesInGroups.contains(objective),
          );

    return remainingBottomSheetObjectives ?? [];
  }

  Widget _buildBackChevron(FlowController<OnboardingFlow> flowController) {
    return SizedBox(
      height: 52,
      width: 44,
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => flowController.update(
            (_) => OnboardingFlow.gradingObjectives,
          ),
          child: FaIcon(
            FontAwesomeIcons.chevronLeft,
            color: primaryLightest,
          ),
        ),
      ),
    );
  }

  Widget buildGroups({
    @required Rubric rubric,
    @required BuildContext context,
  }) {
    final state = context.read(rubricProviderRef);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rubric.groups.mapWithIndex(
        (i, group) {
          return Column(
            children: [
              RubricTextField(
                hintText: group.title,
                onEditingComplete: (value) {
                  // SHAWN!!
                  state.updateTitleForGroup(existingGroup: group, title: value);
                },
              ),
              SizedBox(height: 24),
              ..._buildGroupObjectives(
                rubricObjectives: rubric.objectives,
                group: group,
                context: context,
              ),
              SizedBox(height: 16),
              _buildDragTarget(
                context: context,
                text: 'Add to ${group.title}',
                existingGroup: group,
              )
            ],
          );
        },
      ).joinWith(SizedBox(height: 32)),
    );
  }

  List<Widget> _buildGroupObjectives({
    @required List<Objective> rubricObjectives,
    @required RubricGroup group,
    @required BuildContext context,
  }) {
    final deviceWidth = MediaQuery.of(context).size.width;

    return group.objectives.map(
      (objective) {
        final rubricObjectiveLocation = rubricObjectives.indexOf(objective) + 1;

        final rubricCard = RubricCard(
          cardHintText: 'Objective $rubricObjectiveLocation',
          cardTitleText: objective.title,
        );

        return Draggable(
          data: objective,
          feedback: Container(
            width: deviceWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                color: Colors.transparent,
                child: rubricCard,
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: .4, child: rubricCard),
          child: rubricCard,
        );
      },
    ).joinWith(SizedBox(height: 16));
  }

  Widget _buildDragTarget({
    @required BuildContext context,
    @required String text,
    RubricGroup existingGroup,
  }) {
    final rubricGroupLength =
        context.read(rubricProviderRef.state).groups.length;

    return DragTarget<Objective>(
      builder: (BuildContext context, List<dynamic> l1, List<dynamic> l2) {
        return DottedBorder(
          borderType: BorderType.RRect,
          dashPattern: [4, 4, 4, 4],
          color: lightGray,
          radius: Radius.circular(12),
          child: Container(
            height: 85,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
            child: Center(child: BodyPlaceholder(text, color: lightGray)),
          ),
        );
      },
      onAccept: existingGroup == null
          ? _newGroupCallback(
              context: context,
              nextGroupNumber: rubricGroupLength + 1,
            )
          : _existingGroupCallback(
              context: context,
              existingGroup: existingGroup,
            ),
      onWillAccept: (value) {
        return true;
      },
    );
  }

  void Function(Objective) _newGroupCallback({
    @required BuildContext context,
    @required int nextGroupNumber,
  }) {
    return (value) {
      final objectives = [value];
      final group = RubricGroup(
        title: 'Group $nextGroupNumber',
        objectives: objectives,
      );
      final state = context.read(rubricProviderRef);

      state.addOrMoveObjectiveToNewGroup(
        groupToAdd: group,
        objective: value,
      );
    };
  }

  void Function(Objective) _existingGroupCallback({
    @required BuildContext context,
    @required RubricGroup existingGroup,
  }) {
    return (value) {
      final objectives = [...existingGroup.objectives, value];
      final group = existingGroup.copyWith(objectives: objectives);
      final state = context.read(rubricProviderRef);

      state.moveObjectiveFromExistingGroup(
        existingGroup: existingGroup,
        replacementGroup: group,
        objective: value,
      );
    };
  }

  List<Widget> _buildRubricObjectives({
    @required List<Objective> rubricObjectives,
    @required List<Objective> bottomSheetObjectives,
    @required BuildContext context,
  }) {
    final deviceWidth = MediaQuery.of(context).size.width;

    return bottomSheetObjectives.mapWithIndex(
      (i, objective) {
        final rubricObjectiveLocation = rubricObjectives.indexOf(objective) + 1;
        final rubricCard = RubricCard(
          cardHintText: 'Objective $rubricObjectiveLocation',
          cardTitleText: objective.title,
        );

        return Draggable(
          data: objective,
          feedback: Container(
            width: deviceWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                color: Colors.transparent,
                child: rubricCard,
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: .4, child: rubricCard),
          child: rubricCard,
        );
      },
    ).joinWith(SizedBox(height: 16));
  }
}

//ToDo:
// - Sync group title with text field value
// - For 2.25: Get actual Group Names to sync up with Draggable Area Group Name
