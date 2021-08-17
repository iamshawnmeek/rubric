// import 'package:flutter/foundation.dart'; //null safety stated this was not used.

class Rubric {
  final List<Objective> objectives;
  final List<RubricGroup> groups;

  const Rubric({required this.objectives, required this.groups});

  Rubric copyWith(
      {required List<Objective> objectives,
      required List<RubricGroup> groups}) {
    return Rubric(
      objectives: objectives = this.objectives,
      groups: groups = this.groups,
    );
  }
}

class RubricGroup {
  final String title;
  final List<Objective> objectives;

  RubricGroup({required this.title, required this.objectives});

  RubricGroup copyWith(
      {required String title, required List<Objective> objectives}) {
    return RubricGroup(
      title: title = this.title,
      objectives: objectives = this.objectives,
    );
  }
}

class Objective {
  final String title;

  const Objective({required this.title});
}
