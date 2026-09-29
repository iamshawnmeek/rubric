import 'package:flutter/material.dart';
import 'package:rubric/design_system/design_system.dart';

/// The steps of building a rubric, in order. The v1 onboarding screens
/// (objectives → groups → weights → grading scale) become these steps.
enum BuilderStep { objectives, groups, weights, scale, review }

// STUB — owned by the rubric-builder leaf. Replace wholesale.
class RubricBuilderPage extends StatelessWidget {
  const new({
    required this.rubricId,
    this.step = BuilderStep.objectives,
    this.firstRun = false,
    super.key,
  });

  /// `new` creates a fresh rubric; anything else edits that rubric.
  final String rubricId;
  final BuilderStep step;

  /// True when reached from first-run onboarding: finishing marks onboarding
  /// complete and lands on Home.
  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    return const RubricPage(title: 'Build Rubric');
  }
}
