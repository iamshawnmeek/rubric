import 'package:flow_builder/flow_builder.dart';
import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/set_grading_scale_button.dart';
import 'package:rubric/l10n/l10n.dart';
import 'package:rubric/typography/body_headline.dart';
import 'package:rubric/typography/body_grading_scale_input.dart';
import 'package:rubric/typography/toggle_button_title_active.dart';
import 'package:rubric/typography/toggle_button_title_inactive.dart';

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
          child: DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  child: BodyHeadline(l.gradingScaleTitle),
                ),
                SizedBox(height: 22),
                TabBar(
                  tabs: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child:
                          ToggleButtonTitleActive(l.gradingScaleToggleSimple),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child:
                          ToggleButtonTitleActive(l.gradingScaleToggleDetailed),
                    ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _spacingBetweenRows(),
                          _gradingScaleRow(
                              l: l, low: '90', high: '100', gradeTitle: 'A'),
                          _spacingBetweenRows(),
                          _gradingScaleRow(
                              l: l, low: '80', high: '89.9', gradeTitle: 'B'),
                          _spacingBetweenRows(),
                          _gradingScaleRow(
                              l: l, low: '70', high: '79.9', gradeTitle: 'C'),
                          _spacingBetweenRows(),
                          _gradingScaleRow(
                              l: l, low: '60', high: '69.9', gradeTitle: 'D'),
                          _spacingBetweenRows(),
                          _gradingScaleRow(
                              l: l, low: '50', high: '59.9', gradeTitle: 'F'),
                        ],
                      ),
                      Container(),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: SetGradingScaleButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  SizedBox _spacingBetweenRows() => SizedBox(height: 32);

  Widget _gradingScaleRow({
    @required String gradeTitle,
    @required String low,
    @required String high,
    @required AppLocalizations l,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        BodyGradingScaleInput(gradeTitle),
        Container(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            child: BodyGradingScaleInput(low),
          ),
          decoration: BoxDecoration(
              color: primary, borderRadius: BorderRadius.circular(10)),
        ),
        BodyGradingScaleInput(l.gradingScaleTo),
        Container(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            child: BodyGradingScaleInput(high),
          ),
          decoration: BoxDecoration(
              color: primary, borderRadius: BorderRadius.circular(10)),
        ),
      ],
    );
  }
// TODO: See below
//X. You didn’t use any widgets that actually “do” anything. Maybe use a TabBarView instead of building out widgets for the buttons? The buttons can work, but you’ll have to make your own animations and such between the simple and detailed views.
//What to do with this? Thinking through the next steps.

//X. Fix the warning

//X. Fix how rows / text appear on other devices / testing

//X. Make small adjustments to inconsistent sizes of containers / padding in inputs.
}
