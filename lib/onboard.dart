import 'package:flutter/material.dart';
import 'package:rubric/typography/body_one.dart';
import 'package:rubric/typography/body_placeholder.dart';
import 'package:rubric/typography/body_placeholder_white.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/typography/headline_one.dart';

class Onboard extends StatefulWidget {
  @override
  _OnboardState createState() => _OnboardState();
}

class _OnboardState extends State<Onboard> {
  bool canContinue = false;

  void handleObjectiveChanged(String value) {
    setState(() => canContinue = value.isNotEmpty);
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
                  HeadlineOne('Let’s create your first rubric.'),
                  SizedBox(height: 45),
                  _FormLayer(onObjectiveChanged: handleObjectiveChanged),
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
                      print('clicked');
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
    @required this.onObjectiveChanged,
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
          BodyOne('What is your first grading objective?'),
          SizedBox(height: 36),
          TextField(
            onChanged: onObjectiveChanged,
            style: BodyPlaceholderWhite.textStyle,
            decoration: InputDecoration.collapsed(
              hintText: 'Grammar, usage and mechanics',
              hintStyle: BodyPlaceholder.textStyle,
            ),
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
