import 'package:flutter/material.dart';
import 'package:rubric/design_system/design_system.dart';

// STUB — owned by the feature leaf that builds this screen. Replace wholesale.
class NewAssignmentPage extends StatelessWidget {
  const new({required this.courseId, super.key});

  final String courseId;
  @override
  Widget build(BuildContext context) {
    return const RubricPage(title: 'New Assignment');
  }
}
