import 'package:flutter/material.dart';
import 'package:flow_builder/flow_builder.dart';
import 'package:onboarding/onboarding.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/rubric_logo.dart';
import 'package:rubric/l10n/l10n.dart';

class RubricOnboarding extends StatelessWidget {
  final FlowController flowController;

  RubricOnboarding({Key key, @required this.flowController}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _RubricLogo(),
          _BottomSheet(),
        ],
      ),
    );
  }
}

class _BottomSheet extends StatelessWidget {
  const _BottomSheet({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const pageTitleStyle = TextStyle(
      fontFamily: 'Avenir-Black',
      fontSize: 36,
      height: 1.2,
      color: Colors.white,
    );

    const pageInfoStyle = TextStyle(
      fontFamily: 'Avenir-Heavy',
      fontSize: 24,
      height: 1.5,
      color: primaryLighter,
    );

    final onboardingPagesList = [
      PageModel(
        widget: Container(
          margin: EdgeInsets.only(left: 12, right: 12),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
            ),
            color: primary,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min, //vertical
              crossAxisAlignment: CrossAxisAlignment.stretch, //horizontal
              children: [
                Container(
                    //be as large as possible within parent
                    width: double.infinity,
                    child: Text(l.onboarding1Title, style: pageTitleStyle)),
                SizedBox(height: 42),
                Container(
                  width: double.infinity,
                  child: Text(
                    l.onboarding1Message,
                    style: pageInfoStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];

    return Stack(
      children: [
        Container(color: Colors.black.withOpacity(0.4)),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            color: primary,
            child: Onboarding(
              background: Color(0xff1C0139),
              pagesContentPadding: EdgeInsets.zero,
              footerPadding: EdgeInsets.only(left: 45, right: 12, bottom: 45),
              isSkippable: false,
              pages: onboardingPagesList,
              indicator: Indicator(
                activeIndicator: ActiveIndicator(color: accent), //wip
                indicatorDesign: IndicatorDesign.polygon(
                  polygonDesign: PolygonDesign(
                    polygon: DesignType.polygon_circle,
                  ),
                ),
              ),
              proceedButtonStyle: ProceedButtonStyle(
                proceedButtonColor: accent,
                proceedButtonBorderRadius: BorderRadius.circular(10),
                proceedButtonPadding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 12,
                ),
                proceedpButtonText: Text(
                  l.nextTitle,
                  style: TextStyle(
                    fontFamily: 'Avenir-Heavy',
                    fontSize: 18,
                    height: 1.3,
                    color: secondary,
                  ),
                ),
                proceedButtonRoute: (_) {
                  print('Success!');
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RubricLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: height * .3), //MQ Use
          RubricLogo(),
        ],
      ),
    );
  }
}
