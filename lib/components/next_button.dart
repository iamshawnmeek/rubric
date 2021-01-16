import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/typography/card_next.dart';

class NextButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * .25),
      child: Container(
        height: 75,
        child: Center(
          child: CardNext('Next'),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 18,
        ),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}