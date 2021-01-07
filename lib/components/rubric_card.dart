import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/typography/card_hint.dart';
import 'package:rubric/typography/card_title.dart';

class RubricCard extends StatelessWidget {
  const RubricCard({
    Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHint('Objective 1'),
          SizedBox(height: 7),
          CardTitle('Code Requirements')
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        color: primaryCard,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
