import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flow_builder/flow_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/assign_groups_landing.dart';
import 'package:rubric/assign_weights.dart';
import 'package:rubric/components/colors.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/weight/weight_controller.dart';
import 'package:rubric/enums.dart';
import 'package:rubric/fade_in_page.dart';
import 'package:rubric/grading_objectives_landing.dart';
import 'package:rubric/presentation/regions/assign_weights_view_model.dart';
import 'package:rubric/rubric_grading_scale.dart';
import 'package:rubric/rubric_onboarding.dart';
import 'package:rubric/state/rubric_state.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rubric/l10n/l10n.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
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
  late FlowController<OnboardingFlow> flowController;

  @override
  void initState() {
    super.initState();
    initializeGroupsWhenReady();
    flowController = FlowController<OnboardingFlow>(
      OnboardingFlow
          .gradingScale, //assignWeights, assignWeightsRev, gradingScale
    );
  }

  /// Loops until the l10n is available from the [BuildContext]. Afterwards, we
  /// initialize our groups with our localized values.
  void initializeGroupsWhenReady() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final l = context.maybeL10n;

      if (l == null) {
        initializeGroupsWhenReady();
      } else {
        initializeGroups(l);
      }
    });
  }

  // Adds groups to our Rubric state
  void initializeGroups(AppLocalizations l) {
    final rubric = context.read(rubricProviderRef.notifier);
    rubric.addGroups([
      RubricGroup(title: l.rubricStateTitleOne, objectives: [
        Objective(title: ''),
      ]),
      RubricGroup(title: l.rubricStateTitleTwo, objectives: [
        Objective(title: ''),
      ]),
      RubricGroup(title: l.rubricStateTitleOne, objectives: [
        Objective(title: ''),
      ]),
      RubricGroup(title: l.rubricStateTitleTwo, objectives: [
        Objective(title: ''),
      ]),
    ]);
  }

  @override
  void dispose() {
    flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
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
              FadeInPage(
                  child: RubricOnboarding(flowController: flowController)),
            if (bodyContent == OnboardingFlow.gradingObjectives)
              FadeInPage(
                child: GradingObjectivesLanding(flowController: flowController),
              ),
            if (bodyContent == OnboardingFlow.assignGroups)
              FadeInPage(child: AssignGroupsLanding()),
            if (bodyContent == OnboardingFlow.assignWeights)
              _buildAssignWeights(flowController),
            if (bodyContent == OnboardingFlow.gradingScale)
              FadeInPage(
                  child: RubricGradingScale(flowController: flowController)),
          ];
        },
      ),
    );
  }

  FadeInPage _buildAssignWeights(FlowController flowController) {
    // get our state from riverpod
    final rubric = context.read(rubricProviderRef);

    // get all of the titles of the groups
    final groupNames = rubric.groups.map((group) => group.title).toList();

    // create a weight controller from the group names
    final controller = WeightController.fromNames(groupNames);

    // create a view model to handle the logic for our AssignWeights class
    final viewModel = AssignWeightsViewModel(controller: controller);

    return FadeInPage(
      child: AssignWeights(
        model: viewModel,
        flowController: flowController,
      ),
    );
  }
// TODO:

//- Fix technical debt: updating all strings to include arb file throughout app
// -- 8.20: Working on files rubric_state.dart and assign_groups_landing.dart.
// -- set_grading_scale_button.dart and rubric_grading_scale.dart are good examples of l10n usage.

//- Build in the inputs for each item
//– Build out 'Detailed' view with TabBar
}
