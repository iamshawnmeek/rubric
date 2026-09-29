import 'package:flutter/material.dart';
import 'package:rubric/design_system/design_system.dart';

// STUB — owned by the feature leaf that builds this screen. Replace wholesale.
class StudentPage extends StatelessWidget {
  const new({required this.courseId, required this.studentId, super.key});

  final String courseId;
  final String studentId;
  @override
  Widget build(BuildContext context) {
    return const RubricPage(title: 'Student');
  }
}
