import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:collection/collection.dart';
import 'package:rubric/l10n/l10n.dart';

final rubricProviderRef =
    StateNotifierProvider<RubricState, Rubric>((ref) => RubricState());
//mechanism to update the Rubric class with the new objective

final l = context.l10n;
//unsure where this goes in this context

class RubricState extends StateNotifier<Rubric> {
  RubricState()
      : super(
          Rubric(
            objectives: [],
            groups: [
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
            ],
          ),
        );

  /// Add an objective to master list of objectives
  void addObjective(Objective objective) {
    state = state.copyWith(objectives: [...state.objectives, objective]);
  }

  void updateTitleForGroup({
    required RubricGroup existingGroup,
    required String title,
  }) {
    final replacementGroup = existingGroup.copyWith(title: title);
    final indexOfGroup = state.groups.indexOf(existingGroup);
    final replacementGroups = List<RubricGroup>.from(state.groups)
      ..removeAt(indexOfGroup)
      ..insert(indexOfGroup, replacementGroup);

    state = state.copyWith(groups: replacementGroups);
  }

  /// Add a `group` containing zero or more objectives from [Rubric.objectives]
  void addOrMoveObjectiveToNewGroup({
    required RubricGroup groupToAdd,
    required Objective objective,
  }) {
    final groupsSansObjective = _removeObjectiveFromGroups(objective);
    final replacementGroups = _removeEmptyGroups(groupsSansObjective); //2.24.21

    state = state.copyWith(groups: [...replacementGroups, groupToAdd]);
  }
  // 2.24.21: End: Auto increment group names correctly when dragging objectives to New Group

  // Replace the `existingGroup` in place with the `replacementGroup`
  void moveObjectiveFromExistingGroup({
    required RubricGroup existingGroup,
    required RubricGroup replacementGroup,
    required Objective objective,
  }) {
    final groupsSansObjective = _removeObjectiveFromGroups(
      objective,
    );
    final indexOfGroup = groupsSansObjective.indexOf(existingGroup);
    final replacementGroups = List<RubricGroup>.from(groupsSansObjective)
      ..removeAt(indexOfGroup)
      ..insert(indexOfGroup, replacementGroup);
    final replacementGroupsSansEmpty = _removeEmptyGroups(replacementGroups);

    state = state.copyWith(groups: replacementGroupsSansEmpty);
  }

  List<RubricGroup> _removeEmptyGroups(List<RubricGroup> groups) {
    return groups.where((group) => group.objectives.isNotEmpty).toList();
  }

  List<RubricGroup> _removeObjectiveFromGroups(Objective? objective) {
    // No need to continue if there is no objective
    if (objective == null) return state.groups;

    //find the group that has the duplicate objective
    final groupWithObjective = _findGroupWithObjective(objective);
    final isDraggedFromOtherGroup = groupWithObjective != null;

    if (isDraggedFromOtherGroup) {
      // The objective exists on another group and needs to be removed so
      // there isn't a duplicate objective once we add the objective to the
      // new group
      return _copyGroupsSansObjective(
        groupWithObjective: groupWithObjective!, // null checked on l88
        objectiveForRemoval: objective,
      );
    } else {
      // No need to update the groups in our state, the objective doesn't
      // exist yet
      return state.groups;
    }
  }

  /// Find the first [RubricGroup] containing the [Objective]
  ///
  /// Returns `null` if no group contains the `objective`
  RubricGroup? _findGroupWithObjective(Objective objective) {
    return state.groups.firstWhereOrNull((group) {
      return group.objectives.contains(objective);
    });
  }

  /// Gets a new list of groups without the objective
  ///
  /// Creates a copy of the [Rubric.groups] and replaces the
  /// [RubricGroup.objectives] of the previous
  List<RubricGroup> _copyGroupsSansObjective({
    required RubricGroup groupWithObjective,
    required Objective objectiveForRemoval,
  }) {
    // create copy of objective list so we don't change the original
    final copyOfDraggedGroupObjectives = List<Objective>.from(
      groupWithObjective.objectives,
    );

    // remove objective from group that we've identified
    final removedObjectiveList = copyOfDraggedGroupObjectives
      ..remove(objectiveForRemoval);

    // create copy of group with new objective list
    final groupSansObjective = groupWithObjective.copyWith(
      objectives: removedObjectiveList,
    );

    // find the position of the group in our state where the objective
    // was dragged from
    final indexOfGroup = state.groups.indexOf(groupWithObjective);

    // create a copy of the groups in our state so we don't change
    // the original
    final copyOfStateGroups = List<RubricGroup>.from(state.groups);
    final replacementGroups = copyOfStateGroups
      ..removeAt(indexOfGroup) // remove the group with the dup objective
      ..insert(indexOfGroup, groupSansObjective); // add group sans objective

    return replacementGroups;
  }
}
