import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/l10n/l10n.dart';
import 'package:rubric/typography/card_next.dart';

class SetGradingScaleButton extends StatelessWidget {
  final VoidCallback onTap;

  const SetGradingScaleButton({Key key, @required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final width = MediaQuery.of(context).size.width;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * .225),
      child: Semantics(
        button: true,
        label: l.setGradingScaleTitle,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 75,
            child: Center(
              child: CardNext(l.setGradingScaleTitle),
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
        ),
      ),
    );
  }
}
