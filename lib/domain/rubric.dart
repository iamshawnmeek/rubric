import 'package:flutter/foundation.dart';

class Rubric {
  final List<Objective> objectives;

  const Rubric({@required this.objectives});
}

class Objective {
  final String title;

  const Objective({@required this.title});
}
