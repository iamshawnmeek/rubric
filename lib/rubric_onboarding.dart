import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flow_builder/flow_builder.dart';
import 'package:onboarding/onboarding.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/components/rubric_logo.dart';
import 'package:rubric/l10n/l10n.dart';
import 'package:rubric/enums.dart';

class RubricOnboarding extends StatefulWidget {
  final FlowController flowController;

  RubricOnboarding({Key key, @required this.flowController}) : super(key: key);

  @override
  _RubricOnboardingState createState() => _RubricOnboardingState();
}

class _RubricOnboardingState extends State<RubricOnboarding> {
  @override
  Timer _timer;

  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), () {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          //TODO: Add a 3 sec fade from logo screen to _BottomSheet reveal / fade up. Backdrop fades in and then _BottomSheet fades in from bottom to top.
          _RubricLogo(), //1
          Container(color: Colors.black.withOpacity(0.4)), //2
          _BottomSheet(
            //3
            flowController: widget.flowController,
          ),
        ],
      ),
    );
  }
}

class _BottomSheet extends StatelessWidget {
  final FlowController flowController;
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
  const _BottomSheet({Key key, @required this.flowController})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;

    final onboardingPagesList = [
      _buildPage(title: l.onboarding1Title, message: l.onboarding1Message),
      _buildPage(title: l.onboarding2Title, message: l.onboarding2Message),
      _buildPage(title: l.onboarding3Title, message: l.onboarding3Message),
    ];

    return Align(
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
              activeIndicator: ActiveIndicator(color: primaryLight),
              closedIndicator: ClosedIndicator(color: accent),
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
                  flowController.update(
                    (_) => OnboardingFlow.assignGroups,
                  );
                }),
            skipButtonStyle: SkipButtonStyle(
              skipButtonBorderRadius: _borderRadius,
              skipButtonPadding: _buttonPadding,
              skipButtonText: Text(l.skipTitle, style: _buttonStyle),
            ),
          ),
        ),
      ),
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
