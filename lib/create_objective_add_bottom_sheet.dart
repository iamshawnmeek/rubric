import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rubric/components/colors.dart';
import 'package:rubric/components/rubric_text_field.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:rubric/typography/headline_one.dart';

class CreateObjectiveAddBottomSheet extends ConsumerStatefulWidget {
  final VoidCallback? onPressed;

  const CreateObjectiveAddBottomSheet({
    this.onPressed,
    Key? key,
  }) : super(key: key);

  @override
  _CreateObjectiveAddBottomSheetState createState() =>
      _CreateObjectiveAddBottomSheetState();
}

class _CreateObjectiveAddBottomSheetState
    extends ConsumerState<CreateObjectiveAddBottomSheet> {
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
                  HeadlineOne('Add an Objective'),
                  SizedBox(height: 45),
                  _FormLayer(
                    onObjectiveChanged: handleObjectiveChanged,
                  ),
                  SizedBox(height: 26),
                ],
              ),
              AnimatedPositioned(
                //widget works with Stack
                duration: Duration(milliseconds: 500),
                curve: Curves.ease,
                right: canContinue ? 0 : fabInactivePosition,
                bottom: 0,
                child: Transform.translate(
                  offset: Offset(5, 0),
                  child: FloatingActionButton(
                    foregroundColor: primaryDark,
                    backgroundColor: accent,
                    child: Icon(Icons.add),
                    onPressed: () {
                      // Store the users objective
                      final rubric = ref.read(rubricProviderRef.notifier);
                      rubric.addObjective(Objective(title: objectiveTitle));

                      if (widget.onPressed != null) widget.onPressed!();

                      // Navigate to the grading objectives page
                      Navigator.of(context).pop();
                    },
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
  final void Function(String) onObjectiveChanged;

  const _FormLayer({
    required this.onObjectiveChanged,
    Key? key,
  }) : super(key: key);

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
          RubricTextField(
            onChanged: onObjectiveChanged,
            hintText: 'example: Grammar, usage and mechanics',
            maxLines: 6,
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
