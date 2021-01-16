import 'package:flutter/material.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:rubric/typography/body_one.dart';
import 'package:rubric/typography/body_placeholder.dart';
import 'package:rubric/typography/body_placeholder_white.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/typography/headline_one.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CreateObjectiveAddBottomSheet extends StatefulWidget {
  @override
  _CreateObjectiveAddBottomSheetState createState() =>
      _CreateObjectiveAddBottomSheetState();
}

class _CreateObjectiveAddBottomSheetState
    extends State<CreateObjectiveAddBottomSheet> {
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
            bottom: 36 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Stack(
            overflow: Overflow.visible, // Show FAB outside of this
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
                      final rubric = context.read(rubricProviderRef);
                      rubric.addObjective(Objective(title: objectiveTitle));
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
  final String subtitle;
  final void Function(String) onObjectiveChanged;

  const _FormLayer({
    @required this.onObjectiveChanged,
    this.subtitle,
    Key key,
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
          if (subtitle != null) ...[
            BodyOne(subtitle),
            SizedBox(height: 36),
          ],
          TextField(
            maxLines: 6,
            onChanged: onObjectiveChanged,
            style: BodyPlaceholderWhite.textStyle,
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
