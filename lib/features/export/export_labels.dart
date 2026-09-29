import 'package:rubric/domain/evaluation.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/l10n/l10n.dart';

/// The word shown for an evaluation's status in exported documents.
String statusLabel(AppLocalizations l10n, EvaluationStatus status) =>
    switch (status) {
      EvaluationStatus.notStarted => l10n.exportStatusNotStarted,
      EvaluationStatus.inProgress => l10n.exportStatusInProgress,
      EvaluationStatus.complete => l10n.exportStatusComplete,
      EvaluationStatus.excused => l10n.exportStatusExcused,
      EvaluationStatus.missing => l10n.exportStatusMissing,
    };

String modeLabel(AppLocalizations l10n, GradingMode mode) => switch (mode) {
  GradingMode.simple => l10n.exportModeSimple,
  GradingMode.detailed => l10n.exportModeDetailed,
};
