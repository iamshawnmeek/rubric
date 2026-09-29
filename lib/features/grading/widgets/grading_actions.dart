import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/grading/grading_controller.dart';

/// Shorthand the grading widgets use to reach their controller.
extension GradingRef on WidgetRef {
  GradingController grading(GradingArgs args) =>
      read(gradingControllerProvider(args).notifier);

  /// Applies [change] to the current student, with a selection click when
  /// the teacher has haptics on.
  void gradeEdit(
    GradingArgs args,
    Evaluation Function(Rubric rubric, Evaluation e) change, {
    String? coalesce,
    bool haptic = false,
  }) {
    if (haptic && read(settingsProvider).haptics) {
      unawaited(HapticFeedback.selectionClick());
    }
    grading(args).edit(change, coalesce: coalesce);
  }
}
