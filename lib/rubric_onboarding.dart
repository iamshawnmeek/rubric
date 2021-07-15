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
  static const pageTitleStyle = TextStyle(
    fontFamily: 'Avenir-Black',
    fontSize: 36,
    height: 1.2,
    color: Colors.white,
  );

  static const pageInfoStyle = TextStyle(
    fontFamily: 'Avenir-Heavy',
    fontSize: 24,
    height: 1.5,
    color: primaryLighter,
  );
  const _BottomSheet({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    final onboardingPagesList = [
      _buildPage(title: l.onboarding1Title, message: l.onboarding1Message),
      _buildPage(title: l.onboarding2Title, message: l.onboarding2Message),
      _buildPage(title: l.onboarding3Title, message: l.onboarding3Message),
    ];

    return Stack(
      children: [
        Container(color: Colors.black.withOpacity(0.4)),
        Align(
          alignment: Alignment.bottomCenter,
          child: IntrinsicHeight(
            child: SafeArea(
              child: Onboarding(
                isStandalone: false,
                isSkippable: false,
                background: Colors.transparent,
                pagesContentPadding: EdgeInsets.zero,
                footerPadding: EdgeInsets.all(12).copyWith(left: 45),
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
                    // TODO: make next button navigate to the landing page
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
        ),
      ],
    );
  }

  PageModel _buildPage({
    @required String title,
    @required String message,
  }) {
    return PageModel(
      widget: Container(
        margin: EdgeInsets.only(left: 12, right: 12),
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          color: primary,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(child: Text(title, style: pageTitleStyle)),
            SizedBox(height: 42),
            Container(child: Text(message, style: pageInfoStyle)),
          ],
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
