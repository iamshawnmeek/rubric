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
      color: Color(0xffD2BAED),
    );

    final onboardingPagesList = [
      PageModel(
        widget: Container(
          color: Color(0xff8F53D3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
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
    ];

    return Stack(
      children: [
        Container(color: Colors.black.withOpacity(0.4)),
        Align(
          alignment: Alignment.bottomCenter,
          child: Onboarding(
            isSkippable: false,
            pages: onboardingPagesList,
            indicator: Indicator(
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
