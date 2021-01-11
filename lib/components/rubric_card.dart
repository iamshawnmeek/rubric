import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/typography/card_hint.dart';
import 'package:rubric/typography/card_title.dart';

class RubricCard extends StatelessWidget {
  final String cardHintText;
  final String cardTitleText;

  const RubricCard({
    Key key,
    @required this.cardHintText,
    @required this.cardTitleText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHint(cardHintText),
          SizedBox(height: 7),
          CardTitle(cardTitleText)
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
