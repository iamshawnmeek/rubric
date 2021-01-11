import 'package:flow_builder/flow_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/all.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/enums.dart';
import 'package:rubric/fade_in_page.dart';
import 'package:rubric/grading_objectives_landing.dart';
import 'package:rubric/landing.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(
    ProviderScope(child: MyApp()),
  );
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  FlowController controller;

  @override
  void initState() {
    super.initState();
    controller = FlowController<OnboardingFlow>(
        OnboardingFlow.gradingObjectives); //landing
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: Colors.transparent,
        ),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: secondary,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: FlowBuilder<OnboardingFlow>(
        controller: controller,
        onGeneratePages: (bodyContent, pages) {
          return [
            if (bodyContent == OnboardingFlow.landing)
              FadeInPage(child: Landing(flowController: controller)),
            if (bodyContent == OnboardingFlow.gradingObjectives)
              FadeInPage(child: GradingObjectivesLanding()),
          ];
        },
      ), //Landing
    );
  }
}
