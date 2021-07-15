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
  static final _borderRadius = BorderRadius.circular(10);
  static const _buttonPadding = const EdgeInsets.symmetric(
    horizontal: 30,
    vertical: 12,
  );
  static const _buttonStyle = const TextStyle(
    fontFamily: 'Avenir-Heavy',
    fontSize: 18,
    height: 1.3,
    color: secondary,
  );
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
      _buildPage(l, pageTitleStyle, pageInfoStyle),
      _buildPage(l, pageTitleStyle, pageInfoStyle),
      _buildPage(l, pageTitleStyle, pageInfoStyle),
    ];

    return Stack(
      children: [
        Container(color: Colors.black.withOpacity(0.4)),
        Align(
          alignment: Alignment.bottomCenter,
          child: IntrinsicHeight(
            child: Onboarding(
              isStandalone: false,
              isSkippable: false,
              background: Colors.transparent,
              pagesContentPadding: EdgeInsets.zero,
              footerPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 45),
              pages: onboardingPagesList,
              indicator: Indicator(
                activeIndicator: ActiveIndicator(color: accent),
                indicatorDesign: IndicatorDesign.polygon(
                  polygonDesign: PolygonDesign(
                    polygon: DesignType.polygon_circle,
                  ),
                ),
              ),
              proceedButtonStyle: ProceedButtonStyle(
                proceedButtonColor: accent,
                proceedButtonBorderRadius: _borderRadius,
                proceedButtonPadding: _buttonPadding,
                proceedpButtonText: Text(l.nextTitle, style: _buttonStyle),
                proceedButtonRoute: (_) {
                  print('Success!');
                },
              ),
              skipButtonStyle: SkipButtonStyle(
                skipButtonBorderRadius: _borderRadius,
                skipButtonPadding: _buttonPadding,
                skipButtonText: Text(l.skipTitle, style: _buttonStyle),
              ),
            ),
          ),
        ),
      ],
    );
  }

  PageModel _buildPage(
      AppLocalizations l, TextStyle pageTitleStyle, TextStyle pageInfoStyle) {
    return PageModel(
      widget: Container(
        margin: EdgeInsets.only(left: 12, right: 12),
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(10)),
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
