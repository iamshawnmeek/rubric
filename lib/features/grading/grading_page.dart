import 'package:flutter/material.dart';
import 'package:rubric/design_system/design_system.dart';

// STUB — owned by the feature leaf that builds this screen. Replace wholesale.
class GradingPage extends StatelessWidget {
  const new({required this.assignmentId, required this.studentId, super.key});

  final String assignmentId;
  final String studentId;
  @override
  Widget build(BuildContext context) {
    return const RubricPage(title: 'Grade');
  }
}
