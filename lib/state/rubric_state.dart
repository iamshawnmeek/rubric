import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/domain/rubric.dart';

final rubricProviderRef =
    StateNotifierProvider<RubricState>((ref) => RubricState());

//mechanism to update the Rubric class with the new objective
class RubricState extends StateNotifier<Rubric> {
  RubricState() : super(Rubric(objectives: [], groups: []));

  void addObjective(Objective objective) {
    state = state.copyWith(objectives: [...state.objectives, objective]);
  }

  void addGroup({@required RubricGroup group, @required Objective objective}) {
    //find the group that has the duplicate objective
    final foundGroup = state.groups.firstWhere((group) {
      return group.objectives.contains(objective);
    });

    //create copy of group with new objective list...SM: 2.16
    final foundGroupCopy = state.groups.firstWhere((group) {
      objectives:
      [
        ...state.objectives,
        objective,
      ];
    });

    // WIP Updated: 2.16.21: the types are off: RubricCopy versus Rubric, should be RubricGroup, state.copyWith should change
    // WIP Updated: 2.16.21: reference lines 44 and 45 when updating this

    //...remove objective from group that we've identified

    //replace the current group with the new group
    state = state.copyWith(groups: [...state.groups, group]);
  }

  void replaceGroup({
    @required RubricGroup groupToReplace,
    @required RubricGroup replacementGroup,
  }) {
    final indexOfGroup = state.groups.indexOf(groupToReplace);
    final replacementGroups = List<RubricGroup>.from(state.groups)
      ..removeAt(indexOfGroup)
      ..insert(indexOfGroup, replacementGroup);

    state = state.copyWith(groups: replacementGroups);
  }
}
