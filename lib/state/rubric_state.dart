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

  void addGroup(RubricGroup group) {
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
