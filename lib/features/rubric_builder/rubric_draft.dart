import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/weights.dart';

/// A rubric while it is being built or edited.
///
/// The domain [Rubric] only knows objectives that belong to a group, but the
/// builder collects objectives first and groups them afterwards, so the
/// not-yet-grouped ones live in [ungrouped]. Everything else is the [rubric]
/// itself; [baseline] is what was last loaded or saved, so the page can tell
/// whether leaving would lose work.
@immutable
class RubricDraft {
  const new({
    required this.rubric,
    required this.baseline,
    required this.isNew,
    this.ungrouped = const [],
    this.locked = const {},
  });

  final Rubric rubric;
  final Rubric baseline;

  /// True until the rubric has been saved once.
  final bool isNew;
  final List<Objective> ungrouped;

  /// Ids of groups whose weight is locked while dragging. A tool only — the
  /// weights always sum to 100 whether or not anything is locked.
  final Set<String> locked;

  /// Every objective in display order: grouped ones by group, then the tray.
  List<Objective> get objectives => [...rubric.objectives, ...ungrouped];

  bool get isDirty => ungrouped.isNotEmpty || rubric != baseline;

  /// The scale with bands ordered highest-first, as it will be saved. Rows
  /// are edited in place (so they do not jump while typing) and sorted here.
  GradingScale get sortedScale => GradingScale.sorted(rubric.scale.bands);

  /// Whether the draft can be written to the library as it stands.
  bool get isComplete =>
      ungrouped.isEmpty &&
      rubric.issues.isEmpty &&
      sortedScale.problem == null &&
      rubric.groups.every((g) => g.title.trim().isNotEmpty);

  RubricDraft copyWith({
    Rubric? rubric,
    Rubric? baseline,
    bool? isNew,
    List<Objective>? ungrouped,
    Set<String>? locked,
  }) => RubricDraft(
    rubric: rubric ?? this.rubric,
    baseline: baseline ?? this.baseline,
    isNew: isNew ?? this.isNew,
    ungrouped: ungrouped ?? this.ungrouped,
    locked: locked ?? this.locked,
  );

  @override
  bool operator ==(Object other) =>
      other is RubricDraft &&
      other.rubric == rubric &&
      other.baseline == baseline &&
      other.isNew == isNew &&
      const ListEquality<Objective>().equals(other.ungrouped, ungrouped) &&
      const SetEquality<String>().equals(other.locked, locked);

  @override
  int get hashCode => Object.hash(rubric, baseline, isNew, ungrouped.length);
}

/// Where a deleted objective used to be, so it can be put back exactly.
@immutable
class RemovedObjective {
  const new({
    required this.objective,
    required this.index,
    this.group,
    this.groupIndex,
  });

  final Objective objective;

  /// Position inside its group (or inside the tray when [group] is null).
  final int index;

  /// The group as it was before the removal (null when it was ungrouped).
  final RubricGroup? group;
  final int? groupIndex;
}

/// Whole-number weights for a changed set of groups, keeping the old
/// proportions: [raw] is the previous weights with a share for any new group.
/// Uses [Weights.normalize] and then makes sure no group falls to 0%, taking
/// the point from the heaviest group.
List<int> fitWeights(List<num> raw) {
  final fitted = List<int>.of(Weights.normalize(raw));
  for (var i = 0; i < fitted.length; i++) {
    if (fitted[i] > 0) continue;
    final heaviest = fitted.indexOf(fitted.max);
    if (fitted[heaviest] <= 1) break;
    fitted[heaviest]--;
    fitted[i]++;
  }
  return fitted;
}
