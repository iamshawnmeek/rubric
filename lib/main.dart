import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flow_builder/flow_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/assign_groups_landing.dart';
import 'package:rubric/assign_weights.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/domain/weight/weight_controller.dart';
import 'package:rubric/enums.dart';
import 'package:rubric/fade_in_page.dart';
import 'package:rubric/grading_objectives_landing.dart';
import 'package:rubric/landing.dart';
import 'package:rubric/presentation/regions/region_view_model.dart';
import 'package:rubric/state/rubric_state.dart';

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
  FlowController flowController;

  @override
  void initState() {
    super.initState();
    flowController = FlowController<OnboardingFlow>(
      OnboardingFlow.assignWeights, //assignWeights, assignWeightsRev
    );
  }

  @override
  void dispose() {
    flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: secondary,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: FlowBuilder<OnboardingFlow>(
        controller: flowController,
        onGeneratePages: (bodyContent, pages) {
          return [
            if (bodyContent == OnboardingFlow.landing)
              FadeInPage(child: Landing(flowController: flowController)),
            if (bodyContent == OnboardingFlow.gradingObjectives)
              FadeInPage(
                child: GradingObjectivesLanding(flowController: flowController),
              ),
            if (bodyContent == OnboardingFlow.assignGroups)
              FadeInPage(child: AssignGroupsLanding()),
            if (bodyContent == OnboardingFlow.assignWeights)
              _buildAssignWeights(flowController),
          ];
        },
      ),
    );
  }

  FadeInPage _buildAssignWeights(FlowController flowController) {
    // get our state from riverpod
    final rubric = context.read(rubricProviderRef.state);

    // get all of the titles of the groups
    final groupNames = rubric.groups.map((group) => group.title).toList();

    // create a weight controller from the group names
    final controller = WeightController.fromNames(groupNames);

    // create a view model to handle the logic for our AssignWeights class
    final viewModel = RegionViewModel(controller: controller);

    return FadeInPage(
      child: AssignWeights(
        model: viewModel,
        flowController: flowController,
      ),
    );
  }
}
