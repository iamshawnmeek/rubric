import 'package:flow_builder/flow_builder.dart';
import 'package:flutter/material.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/setGradingScale_button.dart';
import 'package:rubric/l10n/l10n.dart';
import 'package:rubric/typography/body_headline.dart';
import 'package:rubric/typography/toggle_btn_title.dart';
import 'package:rubric/typography/toggle_btn_title_null.dart';

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                child: BodyHeadline(l.gradingScaleTitle),
              ),
              SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: Container(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 60,
                            vertical:
                                12), //note for JW: not sure if this horizontal / width is the right way to do this.
                        child: ToggleBtnTitle(l.gradingScaleToggleSimple),
                      ),
                      decoration: BoxDecoration(
                        color: primaryDark,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 50,
                            vertical:
                                12), //note for JW: not sure if this horizontal / width is the right way to do this.
                        child: ToggleBtnTitleNull(l.gradingScaleToggleDetailed),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              _spacingBetweenRows(),
              _gradingScaleRow(l),
              _spacingBetweenRows(),
              _gradingScaleRow(l),
              _spacingBetweenRows(),
              _gradingScaleRow(l),
              _spacingBetweenRows(),
              _gradingScaleRow(l),
              _spacingBetweenRows(),
              _gradingScaleRow(l),
            ],
          ),
        ),
      ),
      floatingActionButton: SetGradingScaleButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  SizedBox _spacingBetweenRows() => SizedBox(height: 32);

  Row _gradingScaleRow(AppLocalizations l) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ToggleBtnTitleNull(l.gradingScaleGradeA),
        Container(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
            child: ToggleBtnTitleNull('90'),
          ),
          decoration: BoxDecoration(
              color: primary, borderRadius: BorderRadius.circular(10)),
        ),
        ToggleBtnTitleNull(l.gradingScaleTo),
        Container(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
            child: ToggleBtnTitleNull('100'),
          ),
          decoration: BoxDecoration(
              color: primary, borderRadius: BorderRadius.circular(10)),
        ),
      ],
    );
  }

  //Note to JW: I have extracted widgets to become private methods. However, I want to change out lines 91, 95 and 104 to allow other text in these areas. I wanted to extract widgets now to prevent tons of code / repeats for each row later. Also would like to ensure the Containers are text input fields with a default of each of numerical.
}
