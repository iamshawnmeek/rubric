import 'package:flow_builder/flow_builder.dart';
import 'package:flutter/material.dart';
import 'package:rubric/components/setGradingScale_button.dart';
import 'package:rubric/l10n/l10n.dart';
import 'package:rubric/typography/body_headline.dart';

class RubricGradingScale extends StatelessWidget {
  final FlowController flowController;

  const RubricGradingScale({Key key, @required this.flowController})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Container(
            child: BodyHeadline(l.gradingScaleTitle),
          ),
        ),
      ),
      floatingActionButton: SetGradingScaleButton(),
    );
  }
}
