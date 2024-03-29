import 'package:flutter/material.dart';
import 'package:flow_builder/flow_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/enums.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:rubric/typography/body_one.dart';
import 'package:rubric/typography/body_placeholder.dart';
import 'package:rubric/typography/headline_one.dart';

class OnboardingBottomSheet extends ConsumerStatefulWidget {
  const OnboardingBottomSheet({Key? key, required this.flowController})
      : super(key: key);

  final FlowController flowController;

  @override
  _OnboardingBottomSheetState createState() => _OnboardingBottomSheetState();
}

class _OnboardingBottomSheetState extends ConsumerState<OnboardingBottomSheet> {
  bool canContinue = false;
  String objectiveTitle = '';

  void handleObjectiveChanged(String value) {
    setState(() {
      canContinue = value.isNotEmpty;
      objectiveTitle = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final deviceWidth = MediaQuery.of(context).size.width;
    const edgeOffset = 40;
    final fabInactivePosition = -deviceWidth - edgeOffset;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        // hide the FAB outside of this
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: primaryDark,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24).copyWith(
            top: 36,
            bottom: 36,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HeadlineOne('Let’s create your first rubric.'),
                  const SizedBox(height: 45),
                  _FormLayer(
                    onObjectiveChanged: handleObjectiveChanged,
                    subtitle: 'What is your first grading objective?',
                  ),
                  const SizedBox(height: 26),
                ],
              ),
              AnimatedPositioned(
                //widget works with Stack
                duration: const Duration(milliseconds: 500),
                curve: Curves.ease,
                right: canContinue ? 0 : fabInactivePosition,
                bottom: 0,
                child: Transform.translate(
                  offset: const Offset(5, 0),
                  child: FloatingActionButton(
                    foregroundColor: primaryDark,
                    backgroundColor: accent,
                    onPressed: () {
                      // Store the users objective
                      final rubric = ref.read(rubricProviderRef.notifier);
                      rubric.addObjective(Objective(title: objectiveTitle));
                      // Navigate to the grading objectives page
                      widget.flowController.update(
                        (_) => OnboardingFlow.gradingObjectives,
                      );
                    },
                    child: const Icon(Icons.add),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormLayer extends StatelessWidget {
  const _FormLayer({
    required this.onObjectiveChanged,
    required this.subtitle,
    Key? key,
  }) : super(key: key);

  final String? subtitle;
  final void Function(String) onObjectiveChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: primary,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subtitle != null) ...[
            BodyOne(subtitle!),
            SizedBox(height: 36),
          ],
          TextField(
            maxLines: 2,
            onChanged: onObjectiveChanged,
            style: BodyPlaceholder.textStyle.copyWith(color: Colors.white),
            decoration: InputDecoration.collapsed(
              hintText: 'example: Grammar, usage and mechanics',
              hintStyle: BodyPlaceholder.textStyle,
            ).copyWith(hintMaxLines: 3),
            keyboardAppearance: Brightness.dark, //iOS only
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 30,
      ),
    );
  }
}
