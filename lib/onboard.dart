import 'package:flutter/material.dart';
import 'package:rubric/body_one.dart';
import 'package:rubric/body_placeholder.dart';
import 'package:rubric/body_placeholder_white.dart';
import 'package:rubric/colors.dart';
import 'package:rubric/headline_one.dart';

class Onboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: primaryDark,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24).copyWith(
            top: 36,
            bottom: 36 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Stack(
            //z access stacking / children
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  HeadlineOne('Let’s create your first rubric.'),
                  SizedBox(height: 45),
                  _FormLayer(),
                  SizedBox(height: 26),
                ],
              ),
              Positioned(
                //widget works with Stack
                right: 0,
                bottom: 0,
                child: Transform.translate(
                  offset: Offset(5, 0),
                  child: FloatingActionButton(
                    foregroundColor: primaryDark,
                    backgroundColor: accent,
                    child: Icon(Icons.add),
                    onPressed: () {},
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
