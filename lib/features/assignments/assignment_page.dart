import 'package:flutter/material.dart';
import 'package:rubric/design_system/design_system.dart';

// STUB — owned by the feature leaf that builds this screen. Replace wholesale.
class AssignmentPage extends StatelessWidget {
  const new({required this.courseId, required this.assignmentId, super.key});

  final String courseId;
  final String assignmentId;
  @override
  Widget build(BuildContext context) {
    return const RubricPage(title: 'Assignment');
  }
}
