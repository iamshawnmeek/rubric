import 'package:flutter/foundation.dart';

class Rubric {
  final List<Objective> objectives;
  final List<RubricGroup> groups;

  const Rubric({@required this.objectives, @required this.groups});

  Rubric copyWith({List<Objective> objectives, List<RubricGroup> groups}) {
    return Rubric(
      objectives: objectives ?? this.objectives,
      groups: groups ?? this.groups,
    );
  }
}

class RubricGroup {
  final String title;
  final List<Objective> objectives;

  RubricGroup({@required this.title, @required this.objectives});

  RubricGroup copyWith({String title, List<Objective> objectives}) {
    return RubricGroup(
      title: title ?? this.title,
      objectives: objectives ?? this.objectives,
    );
  }
}

class Objective {
  final String title;

  const Objective({@required this.title});
}
