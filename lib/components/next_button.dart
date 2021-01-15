import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/typography/card_next.dart';

class NextBtn extends StatelessWidget {
  const NextBtn({
    Key key,
    @required this.width,
  }) : super(key: key);

  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * .175),
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
