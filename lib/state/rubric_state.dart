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
    }, orElse: () {
      return null;
    });

    if (foundGroup != null) {
      //...remove objective from group that we've identified
      final removedObjectiveList = List<Objective>.from(foundGroup.objectives)
        ..remove(objective);

      //create copy of group with new objective list...SM: 2.16
      final foundGroupCopy = foundGroup.copyWith(
        objectives: removedObjectiveList,
      );

      final indexOfGroup = state.groups.indexOf(foundGroup);

      final replacementGroups = List<RubricGroup>.from(state.groups)
        ..removeAt(indexOfGroup)
        ..insert(indexOfGroup, foundGroupCopy);

      //replace the current group with the new group
      state = state.copyWith(groups: [...replacementGroups, group]);
    } else {
      state = state.copyWith(groups: [...state.groups, group]);
    }
  }

  //refactor lines 16 - 45
  //fix duplication of drag objective to new group in replaceGroup function

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
