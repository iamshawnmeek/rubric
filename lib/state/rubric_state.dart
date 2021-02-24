import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/domain/rubric.dart';

final rubricProviderRef =
    StateNotifierProvider<RubricState>((ref) => RubricState());

//mechanism to update the Rubric class with the new objective
class RubricState extends StateNotifier<Rubric> {
  RubricState() : super(Rubric(objectives: [], groups: []));

  /// Add an objective to master list of objectives
  void addObjective(Objective objective) {
    state = state.copyWith(objectives: [...state.objectives, objective]);
  }

  /// Add a `group` containing zero or more objectives from [Rubric.objectives]
  void addOrMoveObjectiveToNewGroup({
    @required RubricGroup groupToAdd,
    @required Objective objective,
  }) {
    final groupsSansObjective = _removeObjectiveFromGroups(objective);

    state = state.copyWith(groups: [...groupsSansObjective, groupToAdd]);
  }

  // Replace the `existingGroup` in place with the `replacementGroup`
  void moveObjectiveFromExistingGroup({
    @required RubricGroup existingGroup,
    @required RubricGroup replacementGroup,
    @required Objective objective,
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

  List<RubricGroup> _removeObjectiveFromGroups(Objective objective) {
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
        groupWithObjective: groupWithObjective,
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
  RubricGroup _findGroupWithObjective(Objective objective) {
    return state.groups.firstWhere((group) {
      return group.objectives.contains(objective);
    }, orElse: () {
      return null;
    });
  }

  /// Gets a new list of groups without the objective
  ///
  /// Creates a copy of the [Rubric.groups] and replaces the
  /// [RubricGroup.objectives] of the previous
  List<RubricGroup> _copyGroupsSansObjective({
    @required RubricGroup groupWithObjective,
    @required Objective objectiveForRemoval,
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
