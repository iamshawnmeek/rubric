import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/l10n/l10n.dart';

extension RubricLabels on AppLocalizations {
  String modeLabel(GradingMode mode) => switch (mode) {
    GradingMode.simple => rubricsModeSimple,
    GradingMode.detailed => rubricsModeDetailed,
  };

  String issueLabel(RubricIssue issue) => switch (issue) {
    RubricIssue.noTitle => rubricsIssueNoTitle,
    RubricIssue.noGroups => rubricsIssueNoGroups,
    RubricIssue.emptyGroup => rubricsIssueEmptyGroup,
    RubricIssue.weightsNotHundred => rubricsIssueWeights,
    RubricIssue.noLevels => rubricsIssueNoLevels,
    RubricIssue.duplicateLevelPoints => rubricsIssueDuplicateLevelPoints,
  };

  String titleOf(Rubric rubric) =>
      rubric.title.trim().isEmpty ? rubricsUntitled : rubric.title;

  /// "Subject · 6 objectives · Detailed", led by [lead] instead of the subject
  /// when given (a template's grade band).
  String rubricHint(Rubric rubric, {String? lead}) => [
    lead ?? rubric.subject.trim(),
    rubricsObjectiveCount(rubric.objectives.length),
    modeLabel(rubric.mode),
  ].where((part) => part.isNotEmpty).join(' · ');
}

/// Centres page content at a readable width on tablets, keeping the brand
/// background either side.
class RubricsContentWidth extends StatelessWidget {
  const new({required this.child, super.key});

  static const maxWidth = 768.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: secondary,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// A trailing chevron for tappable cards.
class CardChevron extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const FaIcon(
      FontAwesomeIcons.chevronRight,
      color: primaryLightest,
      size: 18,
    );
  }
}
