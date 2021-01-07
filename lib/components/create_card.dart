import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/components/colors.dart';

class CreateCard extends StatelessWidget {
  const CreateCard({
    Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: .5,
      child: Container(
        height: 92,
        child: Center(
          child: FaIcon(FontAwesomeIcons.plus),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 18,
        ),
        decoration: BoxDecoration(
          color: primaryCard,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
